// Local fault injection only: no Firebase project, mail or real user is touched.
// ignore_for_file: subtype_of_sealed_class, must_be_immutable
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:micomunidad/services/attachment_delivery.dart';
import 'package:micomunidad/services/file_service.dart';
import 'package:micomunidad/services/pending_upload_service.dart';

import 'report_delivery_test.dart'
    show
        DeliveryDatabase,
        DeliveryStorage,
        DeliveryCollection,
        DeliveryDocument,
        fakeAttachmentRegistration;
import 'content_creation_draft_test.dart' show DraftSnapshot;

class UploadDatabase extends DeliveryDatabase {
  final parents = <String, Map<String, dynamic>>{
    'projects/demo-project': {'isTrashed': false},
    'events/demo-project': {'title': 'Fictional meeting'},
    'reports/demo-project': {
      'status': 'pendiente',
      'moderationStatus': 'aprobado',
      'createdBy': 'owner'
    },
  };
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      UploadCollection(this, path);
}

class UploadCollection extends DeliveryCollection {
  UploadCollection(super.db, super.path);
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      '${this.path}/$path'.split('/').length == 2
          ? UploadParent(db as UploadDatabase, '${this.path}/$path')
          : super.doc(path);
}

class UploadParent extends DeliveryDocument {
  UploadParent(super.db, super.path);
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get(
      [GetOptions? options]) async {
    final error = db.readError?.call(path);
    if (error != null) throw error;
    return DraftSnapshot((db as UploadDatabase).parents[path],
        cached: db.fromCache, pending: db.pending);
  }
}

const queueKey = 'pending_community_uploads_v1';

class ControlledDelivery implements AttachmentDelivery {
  final calls = <PendingAttachment>[];
  Future<void> Function(PendingAttachment)? operation;
  @override
  Future<void> deliver(PendingAttachment item) async {
    calls.add(item);
    await operation?.call(item);
  }
}

FirebaseException offline() =>
    FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');

Future<List<Map<String, dynamic>>> queue() async {
  final preferences = await SharedPreferences.getInstance();
  return (jsonDecode(preferences.getString(queueKey) ?? '[]') as List)
      .cast<Map<String, dynamic>>();
}

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 1000; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('The local operation did not reach the expected stage.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late File source;
  late String? currentUser;
  late UploadDatabase database;
  late DeliveryStorage storage;
  late FirebaseAttachmentDelivery delivery;
  late PendingUploadService service;

  PendingAttachment item(
          {String collection = 'projects',
          String kind = 'photos',
          String name = 'fictional.png'}) =>
      PendingAttachment(
          id: 'stable-upload',
          collection: collection,
          documentId: 'demo-project',
          kind: kind,
          localPath: source.path,
          name: name,
          userId: 'owner');

  PendingUploadService makeService(AttachmentDelivery sender) =>
      PendingUploadService(
          delivery: sender,
          currentUserId: () => currentUser,
          projectId: () => 'demo-upload-test',
          supportDirectory: () async => temporary);

  Future<bool> upload(
          {String collection = 'projects',
          String kind = 'photos',
          String name = 'fictional.png'}) =>
      service.uploadOrQueue(
          collection: collection,
          documentId: 'demo-project',
          kind: kind,
          selected: SelectedUpload(
              PlatformFile(name: name, size: 3, path: source.path)));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temporary = await Directory.systemTemp.createTemp('attachment-dedup-test-');
    source = File('${temporary.path}/fictional.png');
    await source.writeAsBytes([1, 2, 3]);
    currentUser = 'owner';
    database = UploadDatabase();
    storage = DeliveryStorage();
    delivery = FirebaseAttachmentDelivery(
        firestore: database,
        storage: storage,
        currentUserId: () => currentUser,
        registerAttachment: fakeAttachmentRegistration(database, storage),
        refreshAuth: () async {});
    service = makeService(delivery);
  });

  tearDown(() async {
    final path = await temporary.resolveSymbolicLinks();
    expect(
        temporary.uri.pathSegments
            .any((p) => p.startsWith('attachment-dedup-test-')),
        true);
    await Directory(path).delete(recursive: true);
  });

  for (final scenario in [
    ('projects', 'photos', 'fictional.png'),
    ('reports', 'photos', 'fictional.jpg'),
    ('events', 'photos', 'fictional.jpeg'),
    ('events', 'minutes', 'minutes.pdf'),
    ('events', 'minutes', 'minutes.png'),
    ('projects', 'photos', 'photo.webp'),
    ('reports', 'photos', 'photo.WEBP'),
    ('events', 'photos', 'photo.webp'),
    ('events', 'minutes', 'minutes.webp'),
  ]) {
    test(
        '${scenario.$1}/${scenario.$2}/${scenario.$3}: a retry produces one object and one record',
        () async {
      final attachment =
          item(collection: scenario.$1, kind: scenario.$2, name: scenario.$3);
      await delivery.deliver(attachment);
      await delivery.deliver(attachment);
      expect(storage.writes, [attachment.storagePath]);
      expect(database.writes, [attachment.metadataPath]);
      expect(database.rows[attachment.metadataPath],
          containsPair('uploadId', attachment.id));
      expect(database.rows[attachment.metadataPath]!['contentType'],
          scenario.$3.endsWith('.pdf') ? 'application/pdf' : 'image');
    });
  }

  test(
      'foreground and repeated background passes share the same in-flight attachment',
      () async {
    final controlled = ControlledDelivery();
    final acknowledgement = Completer<void>();
    controlled.operation = (_) => acknowledgement.future;
    service = makeService(controlled);
    final first = upload();
    await until(() => controlled.calls.length == 1);
    final background = service.processPending();
    await service.processPending();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controlled.calls, hasLength(1));
    acknowledgement.complete();
    expect(await first, false);
    await background;
    expect(controlled.calls, hasLength(1));
    expect(await queue(), isEmpty);
  });

  test(
      'one queued image after a lost Storage acknowledgement is recovered without a second put',
      () async {
    storage.lostPutAcknowledgement = offline();
    expect(await upload(), false);
    expect(storage.writes, hasLength(1));
    expect(database.rows, hasLength(1));
    expect(await queue(), isEmpty);
  });

  test('URL failure resumes after restart using the already uploaded object',
      () async {
    storage.urlError = offline();
    expect(await upload(), true);
    final saved = PendingAttachment.fromJson((await queue()).single);
    expect(storage.writes, [saved.storagePath]);
    expect(database.rows, isEmpty);
    storage.urlError = null;
    service = makeService(delivery); // New service, same durable manifest.
    await service.processPending();
    expect(storage.writes, [saved.storagePath]);
    expect(database.rows.keys, [saved.metadataPath]);
    expect(await queue(), isEmpty);
  });

  test(
      'a failed metadata create retries with the same document and Storage IDs',
      () async {
    database.writeHook = (_, __) async => throw offline();
    expect(await upload(), true);
    final saved = PendingAttachment.fromJson((await queue()).single);
    database.writeHook = null;
    await service.processPending();
    expect(storage.writes, [saved.storagePath]);
    expect(database.writes, [saved.metadataPath, saved.metadataPath]);
    expect(database.rows, hasLength(1));
    expect(await queue(), isEmpty);
  });

  test(
      'lost metadata acknowledgement is confirmed by a fresh read without another write',
      () async {
    database.writeHook = (path, data) async {
      database.rows[path] = Map.of(data);
      throw offline();
    };
    expect(await upload(), false);
    expect(database.writes, hasLength(1));
    expect(storage.writes, hasLength(1));
    expect(await queue(), isEmpty);
  });

  test(
      'lost metadata acknowledgement AND failed recovery read survive service restart',
      () async {
    database.writeHook = (path, data) async {
      database.rows[path] = Map.of(data);
      database.readError = (_) => offline();
      throw offline();
    };
    expect(await upload(), true);
    database.readError = null;
    database.writeHook = null;
    service = makeService(delivery);
    await service.processPending();
    expect(database.writes, hasLength(1));
    expect(storage.writes, hasLength(1));
    expect(await queue(), isEmpty);
  });

  test('offline precheck queues the photo; reconnect publishes it exactly once',
      () async {
    database.readError = (_) => offline();
    expect(await upload(), true);
    expect(storage.writes, isEmpty);
    final saved = PendingAttachment.fromJson((await queue()).single);
    expect(await File(saved.localPath).readAsBytes(), [1, 2, 3]);
    database.readError = null;
    await service.processPending();
    await service.processPending();
    expect(storage.writes, [saved.storagePath]);
    expect(database.writes, [saved.metadataPath]);
    expect(await queue(), isEmpty);
  });

  test(
      'simultaneous distinct selections retain both queue entries, not two copies of one',
      () async {
    final controlled = ControlledDelivery();
    controlled.operation = (_) async => throw offline();
    service = makeService(controlled);
    expect(
        await Future.wait([upload(name: 'one.png'), upload(name: 'two.png')]),
        [true, true]);
    final pending = await queue();
    expect(pending, hasLength(2));
    expect(pending.map((i) => i['id']).toSet(), hasLength(2));
    controlled.operation = null;
    await service.processPending();
    expect(await queue(), isEmpty);
    expect(controlled.calls.map((i) => i.id).toSet(), hasLength(2));
  });

  test('another account never sends the previous owner queue', () async {
    database.readError = (_) => offline();
    expect(await upload(), true);
    database.readError = null;
    currentUser = 'other';
    await service.processPending();
    expect(storage.writes, isEmpty);
    expect(await queue(), hasLength(1));
    currentUser = 'owner';
    await service.processPending();
    expect(database.rows, hasLength(1));
  });

  test('signed-out submission does not create a local or cloud attachment',
      () async {
    currentUser = null;
    await expectLater(upload(), throwsA(isA<FileUploadException>()));
    expect(await queue(), isEmpty);
    expect(storage.writes, isEmpty);
  });

  test('an account switch during token refresh blocks the upload', () async {
    final sender = FirebaseAttachmentDelivery(
        firestore: database,
        storage: storage,
        currentUserId: () => currentUser,
        refreshAuth: () async => currentUser = 'other');
    await expectLater(sender.deliver(item()), throwsStateError);
    expect(storage.writes, isEmpty);
    expect(database.rows, isEmpty);
  });

  test(
      'existing metadata belonging to a different contribution is never overwritten',
      () async {
    database.rows[item().metadataPath] = {'uploadedBy': 'other'};
    await expectLater(delivery.deliver(item()), throwsStateError);
    expect(storage.writes, isEmpty);
    expect(database.writes, isEmpty);
  });

  test(
      'existing object belonging to a different contribution is never overwritten',
      () async {
    storage.metadata[item().storagePath] = {'uploadedBy': 'other'};
    await expectLater(delivery.deliver(item()), throwsStateError);
    expect(storage.writes, isEmpty);
    expect(database.writes, isEmpty);
  });

  for (final cache in [true, false]) {
    test(
        'unconfirmed ${cache ? 'cached' : 'pending-write'} metadata cannot confirm success',
        () async {
      database.fromCache = cache;
      database.pending = !cache;
      expect(await upload(), true);
      expect(await queue(), hasLength(1));
      expect(storage.writes, isEmpty);
    });
  }

  test(
      'legacy queue entries retain their identifier and gain stable destinations',
      () async {
    final legacy = item().toJson()..remove('completed');
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(queueKey, jsonEncode([legacy]));
    await service.processPending();
    expect(database.rows.keys, [item().metadataPath]);
    expect(storage.writes, [item().storagePath]);
    expect(await queue(), isEmpty);
  });

  test('a completed entry is cleaned without recreating deleted cloud content',
      () async {
    final completed = {...item().toJson(), 'completed': true};
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(queueKey, jsonEncode([completed]));
    await service.processPending();
    expect(storage.writes, isEmpty);
    expect(database.writes, isEmpty);
    expect(await queue(), isEmpty);
  });

  test(
      'missing queued file does not prevent another valid attachment from uploading',
      () async {
    database.readError = (_) => offline();
    await upload(name: 'missing.png');
    await upload(name: 'present.png');
    final pending = await queue();
    await File(pending.first['localPath'] as String).delete();
    database.readError = null;
    await service.processPending();
    expect(database.rows, hasLength(1));
    expect(await queue(), hasLength(1));
  });

  test('a denied metadata create is surfaced and never widens permissions',
      () async {
    database.writeHook = (_, __) async => throw FirebaseException(
        plugin: 'cloud_firestore', code: 'permission-denied');
    await expectLater(upload(), throwsA(isA<FirebaseException>()));
    expect(database.rows, isEmpty);
    expect((await queue()).single['blocked'], true);
    expect(await File((await queue()).single['localPath'] as String).exists(),
        true);
    final writes = database.writes.length;
    await service.processPending();
    expect(database.writes.length, writes);
    database.writeHook = null;
    await service.processPending(retryBlocked: true);
    expect(await queue(), isEmpty);
  });

  for (final code in ['quota-exceeded', 'resource-exhausted', 'unauthorized']) {
    test(
        '$code retains its copy and reports a blocked upload, not a connection failure',
        () async {
      final controlled = ControlledDelivery()
        ..operation = (_) async =>
            throw FirebaseException(plugin: 'firebase_storage', code: code);
      service = makeService(controlled);
      final result = await service.send(
          collection: 'events',
          documentId: 'demo-project',
          kind: 'minutes',
          selected: SelectedUpload(
              PlatformFile(name: 'minutes.pdf', size: 3, path: source.path)));
      expect(result.state.name, 'blocked');
      expect(result.reason, isNot(contains('conexión')));
      expect((await queue()).single['blocked'], true);
      await service.processPending();
      expect(controlled.calls, hasLength(1));
      controlled.operation = null;
      await service.processPending(retryBlocked: true);
      expect(await queue(), isEmpty);
    });
  }
  test('slow upload confirms a durable copy without waiting indefinitely',
      () async {
    final ack = Completer<void>();
    final controlled = ControlledDelivery()..operation = (_) => ack.future;
    service = PendingUploadService(
        delivery: controlled,
        currentUserId: () => currentUser,
        supportDirectory: () async => temporary,
        projectId: () => 'demo-upload-test',
        foregroundWait: const Duration(milliseconds: 20));
    final result = await service.send(
        collection: 'projects',
        documentId: 'demo-project',
        kind: 'photos',
        selected: SelectedUpload(
            PlatformFile(name: 'photo.png', size: 3, path: source.path)));
    expect(result.state.name, 'queued');
    expect(await queue(), hasLength(1));
    final retry = service.processPending();
    ack.complete();
    await retry;
    expect(controlled.calls, hasLength(1));
    expect(await queue(), isEmpty);
  });
  test('an upload persisted for a different Firebase project is not sent',
      () async {
    final controlled = ControlledDelivery()
      ..operation = (_) async => throw offline();
    service = makeService(controlled);
    await upload();
    controlled.operation = null;
    final other = PendingUploadService(
        delivery: controlled,
        currentUserId: () => currentUser,
        supportDirectory: () async => temporary,
        projectId: () => 'other-project');
    expect(await other.pendingFor('owner'), isEmpty);
    await other.processPending();
    expect(controlled.calls, hasLength(1));
    expect(await queue(), hasLength(1));
    await service.processPending();
    expect(await queue(), isEmpty);
  });

  for (final state in ['deleted', 'archived', 'resolved']) {
    test('$state parent retains but blocks its pending attachment', () async {
      database.readError = (_) => offline();
      final collection = state == 'resolved' ? 'reports' : 'projects';
      expect(await upload(collection: collection), true);
      database.readError = null;
      if (state == 'deleted') {
        database.parents.remove('$collection/demo-project');
      } else if (state == 'archived') {
        database.parents['projects/demo-project'] = {'isTrashed': true};
      } else {
        database.parents['reports/demo-project'] = {
          'status': 'resuelto',
          'moderationStatus': 'aprobado',
          'createdBy': 'owner'
        };
      }
      await service.processPending();
      expect((await queue()).single['blocked'], true);
      expect(storage.writes, isEmpty);
      expect(database.rows, isEmpty);
    });
  }
  test(
      'bytes-only selections get a flushed durable copy before offline confirmation',
      () async {
    final controlled = ControlledDelivery()
      ..operation = (_) async => throw offline();
    service = makeService(controlled);
    final result = await service.send(
        collection: 'projects',
        documentId: 'demo-project',
        kind: 'photos',
        selected: SelectedUpload(PlatformFile(
            name: 'memory.png', size: 3, bytes: await source.readAsBytes())));
    expect(result.state.name, 'queued');
    expect(
        await File((await queue()).single['localPath'] as String).readAsBytes(),
        [1, 2, 3]);
  });
}
