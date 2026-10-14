import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/models/report_edit.dart';
import 'package:micomunidad/models/user_model.dart';
import 'package:micomunidad/services/report_comment_writer.dart';
import 'package:micomunidad/services/report_deletion_guard.dart';

Map<String, dynamic> report(
        {String moderation = 'aprobado',
        String status = 'resuelto',
        bool deleting = false}) =>
    {
      'title': 'Demo report',
      'createdBy': 'another-demo',
      'moderationStatus': moderation,
      'status': status,
      if (deleting) 'deletionInProgress': true,
    };

Future<FakeFirebaseFirestore> setup(
    {String role = 'vecino',
    String approval = 'aprobado',
    Map<String, dynamic>? data}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc('user-demo').set({
    'role': role,
    'approvalStatus': approval,
  });
  await db.collection('reports').doc('r').set(data ?? report());
  return db;
}

ReportCommentWriter writer(FakeFirebaseFirestore db) =>
    ReportCommentWriter(firestore: db, currentUserId: () => 'user-demo');

void main() {
  for (final role in ['vecino', 'admin']) {
    for (final status in [
      'pendiente',
      'en_revision',
      'en_proceso',
      'resuelto'
    ]) {
      test('$role comments on approved $status without changing its parent',
          () async {
        final before = report(status: status);
        final db = await setup(role: role, data: before);
        await writer(db).add(
            reportId: 'r', text: ' Demo follow-up ', authorName: 'Demo User');
        final ref = db.collection('reports').doc('r');
        expect((await ref.get()).data(), before);
        final comment =
            (await ref.collection('comments').get()).docs.single.data();
        expect(comment['text'], 'Demo follow-up');
        expect(comment['authorId'], 'user-demo');
        expect(comment['createdAt'], isA<Timestamp>());
      });
    }
  }

  for (final entry in {
    'pending moderation': report(moderation: 'pendiente'),
    'rejected moderation': report(moderation: 'rechazado'),
    'rejected operational status': report(status: 'rechazado'),
    'deletion started': report(deleting: true),
  }.entries) {
    test('deny new comment: ${entry.key}', () async {
      final db = await setup(data: entry.value);
      await expectLater(
          writer(db).add(reportId: 'r', text: 'Demo', authorName: 'Demo'),
          throwsA(isA<FirebaseException>()
              .having((e) => e.code, 'code', 'permission-denied')));
      expect(
          (await db.collection('reports').doc('r').collection('comments').get())
              .docs,
          isEmpty);
      expect(
          (await db.collection('reports').doc('r').get()).data(), entry.value);
    });
  }

  test('unapproved user and missing parent do not create orphan comments',
      () async {
    final db = await setup(approval: 'pendiente');
    await expectLater(
        writer(db).add(reportId: 'r', text: 'Demo', authorName: 'Demo'),
        throwsA(isA<FirebaseException>()));
    await expectLater(
        writer(db).add(reportId: 'missing', text: 'Demo', authorName: 'Demo'),
        throwsA(isA<FirebaseException>()));
    expect(
        (await db
                .collection('reports')
                .doc('missing')
                .collection('comments')
                .get())
            .docs,
        isEmpty);
  });

  test('validate comment length before any write', () async {
    final db = await setup();
    for (final text in [' ', 'x' * 1001]) {
      await expectLater(
          writer(db).add(reportId: 'r', text: text, authorName: 'Demo'),
          throwsArgumentError);
    }
    expect(
        (await db.collection('reports').doc('r').collection('comments').get())
            .docs,
        isEmpty);
  });

  test('locking deletion prevents new comments and can be retried safely',
      () async {
    final db = await setup(role: 'admin');
    await writer(db)
        .add(reportId: 'r', text: 'Before lock', authorName: 'Demo');
    final guard =
        ReportDeletionGuard(firestore: db, currentUserId: () => 'user-demo');
    await guard.begin('r');
    await guard.begin('r');
    final parent = (await db.collection('reports').doc('r').get()).data()!;
    expect(parent['deletionInProgress'], isTrue);
    expect(parent['status'], 'resuelto');
    expect(parent['createdBy'], 'another-demo');
    await expectLater(
        writer(db).add(reportId: 'r', text: 'After lock', authorName: 'Demo'),
        throwsA(isA<FirebaseException>()));
    expect(
        (await db.collection('reports').doc('r').collection('comments').get())
            .docs,
        hasLength(1));
  });

  test('only approved admin may start deletion of completed reports', () async {
    for (final role in ['vecino', 'admin']) {
      final db = await setup(
          role: role, approval: role == 'admin' ? 'pendiente' : 'aprobado');
      await expectLater(
          ReportDeletionGuard(firestore: db, currentUserId: () => 'user-demo')
              .begin('r'),
          throwsA(isA<FirebaseException>()));
      expect(
          (await db.collection('reports').doc('r').get())
              .data()!['deletionInProgress'],
          isNull);
    }
    final active =
        await setup(role: 'admin', data: report(status: 'en_proceso'));
    await expectLater(
        ReportDeletionGuard(firestore: active, currentUserId: () => 'user-demo')
            .begin('r'),
        throwsA(isA<FirebaseException>()));
  });

  test(
      'interface allows approved users to comment on resolved reports, not rejected or deleting',
      () {
    final user = AppUser(
        userId: 'user-demo',
        email: 'user@example.com',
        nombre: 'Demo',
        role: UserRole.vecino,
        approvalStatus: 'aprobado',
        joinDate: DateTime.utc(2026),
        communityId: 'demo',
        createdAt: DateTime.utc(2026));
    expect(canUserCommentOnReport(user, report()), isTrue);
    expect(canUserCommentOnReport(user, report(deleting: true)), isFalse);
    expect(
        canUserCommentOnReport(user, report(moderation: 'rechazado')), isFalse);
    expect(
        canAdminChangeReportStatus(
            user.copyWith(role: UserRole.admin), report(deleting: true)),
        isFalse);
  });
}
