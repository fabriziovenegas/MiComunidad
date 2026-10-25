// Test-only SDK doubles; no Firebase project or native network is contacted.
// ignore_for_file: subtype_of_sealed_class, must_be_immutable
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:micomunidad/services/pending_report_service.dart';
import 'package:micomunidad/services/report_delivery.dart';

import 'content_creation_draft_test.dart' show DraftSnapshot;
import 'pending_report_service_test.dart' show reportFields;

class DeliveryDatabase extends Mock implements FirebaseFirestore {
  final rows = <String, Map<String, dynamic>>{};
  final writes = <String>[];
  Object? Function(String)? readError;
  Future<void> Function(String, Map<String, dynamic>)? writeHook;
  bool fromCache = false;
  bool pending = false;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      DeliveryCollection(this, path);
}

class DeliveryCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {
  DeliveryCollection(this.db, this.path);
  final DeliveryDatabase db;
  @override
  final String path;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      DeliveryDocument(db, '${this.path}/$path');
}

class DeliveryDocument extends Mock
    implements DocumentReference<Map<String, dynamic>> {
  DeliveryDocument(this.db, this.path);
  final DeliveryDatabase db;
  @override
  final String path;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      DeliveryCollection(db, '${this.path}/$path');
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get(
      [GetOptions? options]) async {
    expect(options?.source, Source.server);
    final error = db.readError?.call(path);
    if (error != null) throw error;
    return DraftSnapshot(db.rows[path],
        cached: db.fromCache, pending: db.pending);
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    db.writes.add(path);
    await db.writeHook?.call(path, data);
    db.rows[path] = Map.of(data);
  }
}

class DeliveryStorage extends Mock implements FirebaseStorage {
  final metadata = <String, Map<String, String>>{};
  final writes = <String>[];
  Object? lostPutAcknowledgement;
  Object? urlError;
  @override
  Reference ref([String? path]) => DeliveryReference(this, path!);
}

class DeliveryReference extends Mock implements Reference {
  DeliveryReference(this.db, this.fullPath);
  final DeliveryStorage db;
  @override
  final String fullPath;
  @override
  Future<FullMetadata> getMetadata() async {
    final saved = db.metadata[fullPath];
    if (saved == null) {
      throw FirebaseException(
          plugin: 'firebase_storage', code: 'object-not-found');
    }
    return DeliveryMetadata(saved);
  }

  @override
  UploadTask putFile(File file, [SettableMetadata? metadata]) =>
      DeliveryTask(() async {
        if (db.metadata.containsKey(fullPath)) {
          throw FirebaseException(
              plugin: 'firebase_storage', code: 'unauthorized');
        }
        expect(await file.exists(), true);
        db.writes.add(fullPath);
        db.metadata[fullPath] = metadata!.customMetadata!;
        if (db.lostPutAcknowledgement != null) throw db.lostPutAcknowledgement!;
      });
  @override
  Future<String> getDownloadURL() async {
    if (db.urlError != null) throw db.urlError!;
    return 'https://example.com/fictional-photo';
  }
}

class DeliveryMetadata extends Mock implements FullMetadata {
  DeliveryMetadata(this.customMetadata);
  @override
  final Map<String, String> customMetadata;
}

class DeliveryTask extends Mock implements UploadTask {
  DeliveryTask(Future<void> Function() operation)
      : future = operation().then((_) => DeliveryTaskSnapshot());
  final Future<TaskSnapshot> future;
  @override
  Future<R> then<R>(FutureOr<R> Function(TaskSnapshot) onValue,
          {Function? onError}) =>
      future.then(onValue, onError: onError);
}

class DeliveryTaskSnapshot extends Mock implements TaskSnapshot {}

void main() {
  late DeliveryDatabase db;
  late DeliveryStorage storage;
  late PendingReport report;
  late FirebaseReportDelivery sender;
  late Directory temporary;
  late File photo;
  late String user;
  setUp(() async {
    db = DeliveryDatabase();
    storage = DeliveryStorage();
    user = 'owner';
    report = PendingReport(
        id: 'stable',
        userId: 'owner',
        fields: reportFields,
        photoName: 'photo.png');
    sender = FirebaseReportDelivery(
        firestore: db,
        storage: storage,
        currentUserId: () => user,
        refreshAuth: () async {});
    temporary = await Directory.systemTemp.createTemp('report-delivery-test-');
    photo = File('${temporary.path}/photo.png');
    await photo.writeAsBytes([1, 2, 3]);
  });
  tearDown(() async {
    final path = await temporary.resolveSymbolicLinks();
    expect(path, contains('report-delivery-test-'));
    await Directory(path).delete(recursive: true);
  });
  FirebaseException offline() =>
      FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
  void seed() {
    db.rows['reports/stable'] = {
      ...reportFields,
      'createdBy': 'owner',
      'status': 'pendiente',
      'moderationStatus': 'pendiente'
    };
  }

  test('creates the report with original moderation and author defaults',
      () async {
    await sender.ensureReport(report);
    expect(db.rows['reports/stable'], containsPair('createdBy', 'owner'));
    expect(db.rows['reports/stable'],
        containsPair('moderationStatus', 'pendiente'));
    expect(db.rows['reports/stable']!['createdAt'], isA<FieldValue>());
  });
  test(
      'existing report is never overwritten, even if already edited and resolved',
      () async {
    seed();
    db.rows['reports/stable']!['status'] = 'resuelto';
    db.rows['reports/stable']!['title'] = 'Edited';
    await sender.ensureReport(report);
    expect(db.writes, isEmpty);
    expect(db.rows['reports/stable']!['title'], 'Edited');
  });
  test('lost report write acknowledgement is recovered by a fresh read',
      () async {
    db.writeHook = (path, data) async {
      db.rows[path] = Map.of(data);
      throw offline();
    };
    await sender.ensureReport(report);
    expect(db.writes, ['reports/stable']);
  });
  test(
      'resident missing-document read denial still attempts authorized creation',
      () async {
    db.readError = (path) => db.rows[path] == null
        ? FirebaseException(
            plugin: 'cloud_firestore', code: 'permission-denied')
        : null;
    await sender.ensureReport(report);
    expect(db.rows, hasLength(1));
  });
  test('permission rejection is never treated as a confirmed report', () async {
    db.readError = (_) =>
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
    db.writeHook = (_, __) async => throw FirebaseException(
        plugin: 'cloud_firestore', code: 'permission-denied');
    await expectLater(
        sender.ensureReport(report), throwsA(isA<FirebaseException>()));
    expect(db.rows, isEmpty);
  });
  for (final cached in [true, false]) {
    test('cache/pending writes cannot confirm delivery (cache=$cached)',
        () async {
      seed();
      db.fromCache = cached;
      db.pending = !cached;
      await expectLater(
          sender.ensureReport(report), throwsA(isA<FirebaseException>()));
      expect(db.writes, isEmpty);
    });
  }
  test('does not recreate a deleted report while retrying its photo', () async {
    await expectLater(
        sender.ensurePhoto(report, photo), throwsA(isA<StateError>()));
    expect(db.writes, isEmpty);
    expect(storage.writes, isEmpty);
  });
  test('uses one stable object and one stable metadata document', () async {
    seed();
    await sender.ensurePhoto(report, photo);
    await sender.ensurePhoto(report, photo);
    expect(storage.writes, [report.photoStoragePath]);
    expect(db.writes, ['reports/stable/photos/stable']);
  });
  test('lost Storage acknowledgement does not upload a second file', () async {
    seed();
    storage.lostPutAcknowledgement = offline();
    await expectLater(
        sender.ensurePhoto(report, photo), throwsA(isA<FirebaseException>()));
    storage.lostPutAcknowledgement = null;
    await sender.ensurePhoto(report, photo);
    expect(storage.writes, [report.photoStoragePath]);
    expect(db.writes, ['reports/stable/photos/stable']);
  });
  test('metadata failure retries the saved object without overwriting Storage',
      () async {
    seed();
    db.writeHook = (_, __) async => throw offline();
    await expectLater(
        sender.ensurePhoto(report, photo), throwsA(isA<FirebaseException>()));
    db.writeHook = null;
    await sender.ensurePhoto(report, photo);
    expect(storage.writes, hasLength(1));
    expect(db.rows.keys.where((key) => key.contains('/photos/')), hasLength(1));
  });
  test('lost metadata acknowledgement is recovered without duplicate records',
      () async {
    seed();
    db.writeHook = (path, data) async {
      db.rows[path] = Map.of(data);
      throw offline();
    };
    await sender.ensurePhoto(report, photo);
    await sender.ensurePhoto(report, photo);
    expect(storage.writes, hasLength(1));
    expect(db.writes, hasLength(1));
  });
  test('download URL failure keeps same object on retry', () async {
    seed();
    storage.urlError = offline();
    await expectLater(
        sender.ensurePhoto(report, photo), throwsA(isA<FirebaseException>()));
    storage.urlError = null;
    await sender.ensurePhoto(report, photo);
    expect(storage.writes, hasLength(1));
    expect(db.writes, hasLength(1));
  });
  test('does not overwrite an object or metadata owned by another upload',
      () async {
    seed();
    storage.metadata[report.photoStoragePath] = {'uploadedBy': 'someone-else'};
    await expectLater(
        sender.ensurePhoto(report, photo), throwsA(isA<StateError>()));
    expect(storage.writes, isEmpty);
    expect(db.writes, isEmpty);
  });
  test('another account cannot continue an old submission', () async {
    user = 'other';
    await expectLater(sender.ensureReport(report), throwsA(isA<StateError>()));
    await expectLater(
        sender.ensurePhoto(report, photo), throwsA(isA<StateError>()));
    expect(storage.writes, isEmpty);
    expect(db.writes, isEmpty);
  });
  test('report locked for permanent deletion is not modified', () async {
    seed();
    db.rows['reports/stable']!['deletionInProgress'] = true;
    await expectLater(sender.ensureReport(report), throwsA(isA<StateError>()));
    expect(db.writes, isEmpty);
  });

  test(
      'failed token refresh retains the photo without starting a Storage write',
      () async {
    seed();
    sender = FirebaseReportDelivery(
        firestore: db,
        storage: storage,
        currentUserId: () => user,
        refreshAuth: () async => throw offline());
    await expectLater(
        sender.ensurePhoto(report, photo), throwsA(isA<FirebaseException>()));
    expect(storage.writes, isEmpty);
    expect(db.writes, isEmpty);
  });

  test(
      'switching accounts during token refresh cannot upload the old account photo',
      () async {
    seed();
    sender = FirebaseReportDelivery(
        firestore: db,
        storage: storage,
        currentUserId: () => user,
        refreshAuth: () async {
          user = 'other';
        });
    await expectLater(
        sender.ensurePhoto(report, photo), throwsA(isA<StateError>()));
    expect(storage.writes, isEmpty);
    expect(db.writes, isEmpty);
  });
}
