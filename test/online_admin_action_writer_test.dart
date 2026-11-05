import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/services/online_admin_action_writer.dart';

class DisconnectedDatabase extends FakeFirebaseFirestore {
  int attempts = 0;
  @override
  Future<T> runTransaction<T>(TransactionHandler<T> transactionHandler,
      {Duration timeout = const Duration(seconds: 30),
      int maxAttempts = 5}) async {
    attempts++;
    throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
  }
}

void main() {
  for (final archive in [true, false]) {
    test('$archive disconnected transaction never queues a direct write',
        () async {
      final offline = DisconnectedDatabase();
      await offline.doc('projects/one').set({'title': 'keep'});
      await offline.doc('reports/one').set({'status': 'pendiente'});
      final before = offline.dump();
      final writer = OnlineAdminActionWriter(
          firestore: offline, currentUserId: () => 'admin');
      await expectLater(
          archive
              ? writer.archiveProject('one')
              : writer.changeReportStatus('one', 'resuelto'),
          throwsA(isA<FirebaseException>()
              .having((e) => e.code, 'code', 'unavailable')));
      expect(offline.attempts, 1);
      expect(offline.dump(), before);
    });
  }
  late FakeFirebaseFirestore db;
  late OnlineAdminActionWriter writer;
  String? uid;
  setUp(() async {
    db = FakeFirebaseFirestore();
    uid = 'admin';
    writer = OnlineAdminActionWriter(firestore: db, currentUserId: () => uid);
    await db
        .doc('users/admin')
        .set({'role': 'admin', 'approvalStatus': 'aprobado'});
    for (final collection in ['projects', 'reports']) {
      await db.doc('$collection/one').set({
        'title': 'Fictitious',
        'createdBy': 'another',
        'moderationStatus': 'aprobado',
        'status': 'pendiente'
      });
      await db.doc('$collection/one/photos/photo').set({'name': 'keep.png'});
    }
  });
  test('archive preserves project contents and attachments', () async {
    await writer.archiveProject('one');
    final data = (await db.doc('projects/one').get()).data()!;
    expect(data['isTrashed'], true);
    expect(data['title'], 'Fictitious');
    expect(data['createdBy'], 'another');
    expect(data['trashedAt'], isA<Timestamp>());
    expect((await db.doc('projects/one/photos/photo').get()).exists, true);
  });
  test('restore removes trash marker, preserves project and attached contents',
      () async {
    await writer.archiveProject('one');
    await writer.restoreProject('one');
    final data = (await db.doc('projects/one').get()).data()!;
    expect(data['isTrashed'], false);
    expect(data.containsKey('trashedAt'), false);
    expect(data['title'], 'Fictitious');
    expect((await db.doc('projects/one/photos/photo').get()).exists, true);
  });
  test('restore requires an approved administrator', () async {
    await db.doc('users/admin').update({'role': 'vecino'});
    final before = db.dump();
    await expectLater(
        writer.restoreProject('one'), throwsA(isA<FirebaseException>()));
    expect(db.dump(), before);
  });
  test('restore when connection is lost cannot queue the write', () async {
    final db = DisconnectedDatabase();
    await db.doc('projects/one').set({'isTrashed': true});
    final writer =
        OnlineAdminActionWriter(firestore: db, currentUserId: () => 'admin');
    await expectLater(
        writer.restoreProject('one'), throwsA(isA<FirebaseException>()));
    expect((await db.doc('projects/one').get()).data()!['isTrashed'], true);
  });
  for (final status in ['pendiente', 'en_proceso', 'resuelto']) {
    test('approved admin saves $status without changing author or attachments',
        () async {
      await writer.changeReportStatus('one', status);
      final data = (await db.doc('reports/one').get()).data()!;
      expect(data['status'], status);
      expect(data['moderationStatus'], 'aprobado');
      expect(data['createdBy'], 'another');
      expect((await db.doc('reports/one/photos/photo').get()).exists, true);
    });
  }
  for (final archive in [true, false]) {
    for (final profile in [
      {'role': 'vecino', 'approvalStatus': 'aprobado'},
      {'role': 'admin', 'approvalStatus': 'pendiente'},
      {'role': 'admin', 'approvalStatus': 'retirado'},
    ]) {
      test('$archive rejects profile $profile without writing', () async {
        await db.doc('users/admin').set(profile);
        final before = db.dump();
        await expectLater(
            archive
                ? writer.archiveProject('one')
                : writer.changeReportStatus('one', 'resuelto'),
            throwsA(isA<FirebaseException>()
                .having((e) => e.code, 'code', 'permission-denied')));
        expect(db.dump(), before);
      });
    }
    test('$archive missing content is not recreated', () async {
      await expectLater(
          archive
              ? writer.archiveProject('missing')
              : writer.changeReportStatus('missing', 'resuelto'),
          throwsA(isA<FirebaseException>()
              .having((e) => e.code, 'code', 'not-found')));
    });
    test('$archive signed out never writes', () async {
      uid = null;
      final before = db.dump();
      await expectLater(
          archive
              ? writer.archiveProject('one')
              : writer.changeReportStatus('one', 'resuelto'),
          throwsA(isA<FirebaseException>()
              .having((e) => e.code, 'code', 'unauthenticated')));
      expect(db.dump(), before);
    });
  }
  test('pending or rejected reports cannot be marked resolved', () async {
    for (final moderation in ['pendiente', 'rechazado']) {
      await db.doc('reports/one').update({'moderationStatus': moderation});
      await expectLater(writer.changeReportStatus('one', 'resuelto'),
          throwsA(isA<FirebaseException>()));
      expect(
          (await db.doc('reports/one').get()).data()!['status'], 'pendiente');
    }
  });
  test('invalid status never writes', () async {
    final before = db.dump();
    expect(
        () => writer.changeReportStatus('one', 'invalid'), throwsArgumentError);
    expect(db.dump(), before);
  });
}
