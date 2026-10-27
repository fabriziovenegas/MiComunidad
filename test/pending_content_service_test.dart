import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/services/pending_content_service.dart';
import 'package:micomunidad/services/content_delivery.dart';

const projectFields = {
  'title': 'Iluminación de la plaza',
  'description': 'Reparar luminarias.',
  'location': 'Plaza ficticia',
  'progress': 38,
  'status': 'en_proceso'
};
Map<String, dynamic> eventFields() => {
      'title': 'Asamblea vecinal',
      'description': 'Revisión de propuestas.',
      'location': 'Local ficticio',
      'eventDate': Timestamp(1800000000, 123456789)
    };

class ControlledContent implements ContentDelivery {
  ControlledContent(this.actual);
  final ContentDelivery actual;
  int calls = 0;
  Future<void> Function(PendingContent)? before;
  Future<void> Function(PendingContent)? after;
  @override
  Future<void> deliver(PendingContent item) async {
    calls++;
    await before?.call(item);
    await actual.deliver(item);
    await after?.call(item);
  }
}

FirebaseException offline() =>
    FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late FakeFirebaseFirestore db;
  late ControlledContent delivery;
  late String? user;
  PendingContentService service(
          {Duration wait = const Duration(milliseconds: 80)}) =>
      PendingContentService(
          directory: () async => root,
          currentUserId: () => user,
          newId: () => 'stable-id',
          delivery: delivery,
          foregroundWait: wait);
  Future<PendingSendResult> submit(PendingContentService queue,
          {String collection = 'projects',
          String id = 'stable-id',
          String? parentId,
          Map<String, dynamic>? fields}) =>
      queue.submit(
          id: id,
          collection: collection,
          expectedUserId: 'owner',
          parentId: parentId,
          fields: fields ??
              (parentId == null
                  ? collection == 'projects'
                      ? projectFields
                      : eventFields()
                  : {
                      'text': 'Propuesta de prueba',
                      'authorName': 'Lucía Torres'
                    }));
  setUp(() async {
    root = await Directory.systemTemp.createTemp('content-outbox-test-');
    user = 'owner';
    db = FakeFirebaseFirestore();
    await db
        .doc('users/owner')
        .set({'role': 'admin', 'approvalStatus': 'aprobado'});
    await db.doc('projects/parent').set({'isTrashed': false});
    await db.doc('events/parent').set({'title': 'Reunión ficticia'});
    await db
        .doc('reports/parent')
        .set({'moderationStatus': 'aprobado', 'status': 'resuelto'});
    delivery = ControlledContent(
        FirebaseContentDelivery(firestore: db, currentUserId: () => user));
  });
  tearDown(() async {
    final path = await root.resolveSymbolicLinks();
    expect(
        root.uri.pathSegments.any((p) => p.startsWith('content-outbox-test-')),
        true);
    await Directory(path).delete(recursive: true);
  });
  test(
      'queued comments use the current profile name instead of an old supplied name',
      () async {
    await db.doc('users/owner').update({'nombre': 'Fictional Current Name'});
    final item = PendingContent(
        id: 'canonical-name',
        collection: 'projects',
        parentId: 'parent',
        userId: 'owner',
        fields: {
          'text': 'Fictional comment',
          'authorName': 'Forged or old name'
        });
    await delivery.deliver(item);
    final saved =
        (await db.doc('projects/parent/comments/canonical-name').get()).data()!;
    expect(saved['authorName'], 'Fictional Current Name');
    expect(saved['authorId'], 'owner');
  });
  for (final collection in ['projects', 'events']) {
    test(
        '$collection preserves complete fields before network, restores after restart and sends only once',
        () async {
      final queue = service();
      delivery.before = (item) async {
        final pending = await queue.pendingFor('owner');
        expect(pending.single.path, item.path);
        throw offline();
      };
      expect((await submit(queue, collection: collection)).state,
          PendingSendState.queued);
      expect((await db.collection(collection).get()).docs, hasLength(1));
      final recovered = service();
      final saved = (await recovered.pendingFor('owner')).single;
      expect(saved.fields,
          collection == 'projects' ? projectFields : eventFields());
      delivery.before = null;
      await recovered.processPending();
      await recovered.processPending();
      final record = (await db.doc('$collection/stable-id').get()).data()!;
      for (final entry in saved.fields.entries) {
        expect(record[entry.key], entry.value);
      }
      expect(record['createdBy'], 'owner');
      expect(record['createdAt'], isA<Timestamp>());
      if (collection == 'projects') expect(record['isTrashed'], false);
      expect(await recovered.pendingFor('owner'), isEmpty);
    });
    test(
        '$collection retry recovers lost acknowledgement without restoring changed data',
        () async {
      delivery.after = (_) async => throw offline();
      await submit(service(), collection: collection);
      await db.doc('$collection/stable-id').update(collection == 'projects'
          ? {'title': 'Edited after arrival', 'progress': 89, 'isTrashed': true}
          : {'title': 'Edited after arrival'});
      delivery.after = null;
      await service().processPending();
      final data = (await db.doc('$collection/stable-id').get()).data()!;
      expect(data['title'], 'Edited after arrival');
      if (collection == 'projects') {
        expect(data['progress'], 89);
        expect(data['isTrashed'], true);
      }
      expect(await service().pendingFor('owner'), isEmpty);
    });
    test(
        '$collection losing administrator permission retains the draft without creating it',
        () async {
      delivery.before = (_) async => throw offline();
      await submit(service(), collection: collection);
      await db.doc('users/owner').update({'role': 'vecino'});
      delivery.before = null;
      final queue = service();
      await queue.processPending();
      expect((await queue.pendingFor('owner')).single.blocked, true);
      expect((await db.doc('$collection/stable-id').get()).exists, false);
      final calls = delivery.calls;
      await queue.processPending();
      expect(delivery.calls, calls);
      await db.doc('users/owner').update({'role': 'admin'});
      await queue.processPending(retryBlocked: true);
      expect((await db.doc('$collection/stable-id').get()).exists, true);
    });
  }
  for (final collection in ['projects', 'reports', 'events']) {
    test(
        '$collection comments survive restart and lost acknowledgements without duplicates',
        () async {
      await db.doc('users/owner').update({'role': 'vecino'});
      delivery.before = (_) async => throw offline();
      await submit(service(), collection: collection, parentId: 'parent');
      delivery.before = null;
      delivery.after = (_) async => throw offline();
      await service().processPending();
      delivery.after = null;
      await service().processPending();
      await service().processPending();
      final comments =
          (await db.collection('$collection/parent/comments').get()).docs;
      expect(comments, hasLength(1));
      expect(comments.single.id, 'stable-id');
      expect(comments.single.data()['text'], 'Propuesta de prueba');
      expect(comments.single.data()['authorId'], 'owner');
      expect(await service().pendingFor('owner'), isEmpty);
    });
    test('$collection deleted parent blocks and preserves its queued comment',
        () async {
      delivery.before = (_) async => throw offline();
      await submit(service(), collection: collection, parentId: 'parent');
      await db.doc('$collection/parent').delete();
      delivery.before = null;
      await service().processPending();
      expect((await service().pendingFor('owner')).single.blocked, true);
      expect((await db.collection('$collection/parent/comments').get()).docs,
          isEmpty);
    });
  }
  for (final state in ['archived', 'rejected', 'deleting']) {
    test('$state content cannot receive a pending comment', () async {
      final collection = state == 'archived' ? 'projects' : 'reports';
      delivery.before = (_) async => throw offline();
      await submit(service(), collection: collection, parentId: 'parent');
      await db.doc('$collection/parent').update(state == 'archived'
          ? {'isTrashed': true}
          : state == 'rejected'
              ? {'moderationStatus': 'rechazado'}
              : {'deletionInProgress': true});
      delivery.before = null;
      await service().processPending();
      expect((await service().pendingFor('owner')).single.blocked, true);
      expect((await db.collection('$collection/parent/comments').get()).docs,
          isEmpty);
    });
  }
  test(
      'slow response returns a durable confirmation; simultaneous attempts share one send',
      () async {
    final gate = Completer<void>();
    delivery.before = (_) => gate.future;
    final queue = service(wait: const Duration(milliseconds: 20));
    final results = await Future.wait([
      submit(queue),
      submit(queue),
      queue
          .processPending()
          .then((_) => const PendingSendResult(PendingSendState.queued))
    ]);
    expect(results.first.state, PendingSendState.queued);
    expect(delivery.calls, 1);
    expect(await queue.pendingFor('owner'), hasLength(1));
    final retry = queue.processPending();
    gate.complete();
    await retry;
    expect(delivery.calls, 1);
    expect(await queue.pendingFor('owner'), isEmpty);
  });
  test(
      'multiple entries persist independently and a blocked one does not stop the others',
      () async {
    delivery.before = (_) async => throw offline();
    await Future.wait([
      submit(service(), id: 'one'),
      submit(service(), id: 'two', collection: 'events')
    ]);
    delivery.before = (item) async {
      if (item.id == 'one') {
        throw FirebaseException(
            plugin: 'cloud_firestore', code: 'resource-exhausted');
      }
    };
    await service().processPending();
    final remaining = (await service().pendingFor('owner')).single;
    expect(remaining.id, 'one');
    expect(remaining.blocked, true);
    expect((await db.doc('events/two').get()).exists, true);
  });
  test(
      'another account and sign-out cannot send or list previous account drafts',
      () async {
    delivery.before = (_) async => throw offline();
    await submit(service());
    delivery.before = null;
    user = 'other';
    await service().processPending();
    expect(await service().pendingFor('other'), isEmpty);
    user = null;
    await service().processPending();
    expect((await db.doc('projects/stable-id').get()).exists, false);
    user = 'owner';
    await service().processPending();
    expect((await db.doc('projects/stable-id').get()).exists, true);
  });
  test('a resumed app retries durable entries', () async {
    delivery.before = (_) async => throw offline();
    await submit(service());
    delivery.before = null;
    final queue = service();
    final empty = Completer<void>();
    final sub = queue.watch('owner').listen((items) {
      if (items.isEmpty && !empty.isCompleted) empty.complete();
    });
    queue.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await empty.future.timeout(const Duration(seconds: 3));
    await sub.cancel();
    expect((await db.doc('projects/stable-id').get()).exists, true);
  });
  test('disk failure never claims a local save or starts a network request',
      () async {
    final file = File('${root.path}/not-a-directory');
    await file.writeAsString('x');
    final queue = PendingContentService(
        directory: () async => Directory(file.path),
        currentUserId: () => user,
        delivery: delivery);
    await expectLater(submit(queue), throwsA(isA<FileSystemException>()));
    expect(delivery.calls, 0);
  });
  test(
      'sent marker survives cleanup interruption and never recreates deleted records',
      () async {
    final item = PendingContent(
        id: 'done',
        collection: 'projects',
        userId: 'owner',
        fields: projectFields,
        sent: true);
    await File('${root.path}/done.json')
        .writeAsString(jsonEncode(item.toJson()));
    expect((await submit(service(), id: 'done')).state, PendingSendState.sent);
    await service().processPending();
    expect(delivery.calls, 0);
  });
  test('conflicting remote ownership is blocked without overwriting', () async {
    await db
        .doc('projects/stable-id')
        .set({'createdBy': 'other', 'title': 'Keep this'});
    expect((await submit(service())).state, PendingSendState.blocked);
    expect((await db.doc('projects/stable-id').get()).data()!['title'],
        'Keep this');
  });
  test('same ID cannot silently replace different local content', () async {
    delivery.before = (_) async => throw offline();
    final queue = service();
    await submit(queue);
    await expectLater(
        submit(queue, fields: {...projectFields, 'title': 'Changed'}),
        throwsStateError);
    expect((await queue.pendingFor('owner')).single.fields, projectFields);
  });
  test('invalid progress, payload and traversal never get published', () async {
    final queue = service();
    for (final progress in [-1, 101, 1.5]) {
      expect(
          () => submit(queue, fields: {...projectFields, 'progress': progress}),
          throwsArgumentError);
    }
    expect(() => submit(queue, id: '../escape'), throwsFormatException);
    expect(
        () => submit(queue, fields: {...projectFields, 'createdBy': 'other'}),
        throwsFormatException);
    expect(await queue.pendingFor('owner'), isEmpty);
    expect(delivery.calls, 0);
  });
}
