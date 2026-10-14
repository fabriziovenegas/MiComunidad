import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/models/report_edit.dart';
import 'package:micomunidad/services/report_content_editor.dart';

const draft = ReportEditDraft(
  title: ' Edited demo ',
  description: ' Updated description ',
  location: ' Demo location ',
  category: 'obras',
  priority: 'alta',
);

Map<String, dynamic> report({
  String author = 'neighbor-a',
  String moderation = 'aprobado',
  String status = 'en_proceso',
}) =>
    {
      'createdBy': author,
      'createdByName': 'Demo Resident',
      'title': 'Old title',
      'description': 'Old description',
      'location': '',
      'category': 'limpieza',
      'priority': 'media',
      'moderationStatus': moderation,
      'status': status,
      'moderatedBy': 'admin-demo',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
    };

void main() {
  test('approved admin saves own resolved content and preserves its state',
      () async {
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('admin-demo').set({
      'role': 'admin',
      'approvalStatus': 'aprobado',
    });
    final before = report(author: 'admin-demo', status: 'resuelto');
    final ref = db.collection('reports').doc('r');
    await ref.set(before);
    await ReportContentEditor(firestore: db, currentUserId: () => 'admin-demo')
        .save('r', draft);
    final after = (await ref.get()).data()!;
    expect(after['title'], 'Edited demo');
    expect(after['status'], 'resuelto');
    expect(after['moderationStatus'], 'aprobado');
    expect(after['createdBy'], 'admin-demo');
  });

  for (final profile in [
    {'role': 'vecino', 'approvalStatus': 'aprobado'},
    {'role': 'admin', 'approvalStatus': 'pendiente'},
  ]) {
    test('resolved edit requires actual approved admin profile: $profile',
        () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('owner-demo').set(profile);
      final before = report(author: 'owner-demo', status: 'resuelto');
      final ref = db.collection('reports').doc('r');
      await ref.set(before);
      await expectLater(
        ReportContentEditor(firestore: db, currentUserId: () => 'owner-demo')
            .save('r', draft),
        throwsA(isA<FirebaseException>()
            .having((e) => e.code, 'code', 'permission-denied')),
      );
      expect((await ref.get()).data(), before);
    });
  }

  test(
      'administrator author uses the same content save without changing status',
      () async {
    final db = FakeFirebaseFirestore();
    final before = report(author: 'admin-demo');
    await db.collection('reports').doc('r').set(before);
    await ReportContentEditor(firestore: db, currentUserId: () => 'admin-demo')
        .save('r', draft);
    final after = (await db.collection('reports').doc('r').get()).data()!;
    expect(after['title'], 'Edited demo');
    expect(after['createdBy'], 'admin-demo');
    expect(after['status'], before['status']);
    expect(after['moderationStatus'], before['moderationStatus']);
  });

  test('administrator cannot use the content service on another author report',
      () async {
    final db = FakeFirebaseFirestore();
    await db.collection('reports').doc('r').set(report());
    await expectLater(
      ReportContentEditor(firestore: db, currentUserId: () => 'admin-demo')
          .save('r', draft),
      throwsA(isA<FirebaseException>()
          .having((e) => e.code, 'code', 'permission-denied')),
    );
    expect((await db.collection('reports').doc('r').get()).data(), report());
  });

  for (final moderation in ['pendiente', 'aprobado']) {
    for (final status in ['pendiente', 'en_revision', 'en_proceso']) {
      test('save own $moderation/$status without changing administration',
          () async {
        final db = FakeFirebaseFirestore();
        final before = report(moderation: moderation, status: status);
        await db.collection('reports').doc('r').set(before);
        await ReportContentEditor(
            firestore: db, currentUserId: () => 'neighbor-a').save('r', draft);
        final after = (await db.collection('reports').doc('r').get()).data()!;
        expect(after['title'], 'Edited demo');
        expect(after['description'], 'Updated description');
        expect(after['location'], 'Demo location');
        expect(after['updatedAt'], isA<Timestamp>());
        for (final field in [
          'createdBy',
          'createdByName',
          'moderationStatus',
          'status',
          'moderatedBy',
          'createdAt'
        ]) {
          expect(after[field], before[field], reason: field);
        }
        expect(after.keys.toSet(), {...before.keys, 'updatedAt'});
      });
    }
  }

  for (final entry in <String, Map<String, dynamic>>{
    'another author': report(author: 'neighbor-b'),
    'resolved while dialog was open': report(status: 'resuelto'),
    'rejected while dialog was open': report(moderation: 'rechazado'),
    'legacy rejected status': report(status: 'rechazado'),
    'missing moderation': {...report()}..remove('moderationStatus'),
  }.entries) {
    test('reject stale/unauthorized save: ${entry.key}', () async {
      final db = FakeFirebaseFirestore();
      final ref = db.collection('reports').doc('r');
      await ref.set(entry.value);
      await expectLater(
        ReportContentEditor(firestore: db, currentUserId: () => 'neighbor-a')
            .save('r', draft),
        throwsA(isA<FirebaseException>()
            .having((e) => e.code, 'code', 'permission-denied')),
      );
      expect((await ref.get()).data(), entry.value);
    });
  }

  test('require a session and preserve the document', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('reports').doc('r').set(report());
    await expectLater(
      ReportContentEditor(firestore: db, currentUserId: () => null)
          .save('r', draft),
      throwsA(isA<FirebaseException>()
          .having((e) => e.code, 'code', 'unauthenticated')),
    );
    expect((await db.collection('reports').doc('r').get()).data(), report());
  });

  test('reject an account change during a save', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('reports').doc('r').set(report());
    var calls = 0;
    await expectLater(
      ReportContentEditor(
              firestore: db,
              currentUserId: () => ++calls == 1 ? 'neighbor-a' : 'neighbor-b')
          .save('r', draft),
      throwsA(isA<FirebaseException>()
          .having((e) => e.code, 'code', 'permission-denied')),
    );
    expect((await db.collection('reports').doc('r').get()).data(), report());
  });

  test('do not recreate a deleted report', () async {
    final db = FakeFirebaseFirestore();
    await expectLater(
      ReportContentEditor(firestore: db, currentUserId: () => 'neighbor-a')
          .save('deleted', draft),
      throwsA(
          isA<FirebaseException>().having((e) => e.code, 'code', 'not-found')),
    );
    expect((await db.collection('reports').get()).docs, isEmpty);
  });

  test('validate content and whitelist fields', () {
    expect(ReportEditDraft.validateTitle('  '), isNotNull);
    expect(ReportEditDraft.validateTitle('x' * 161), isNotNull);
    expect(ReportEditDraft.validateDescription('\n '), isNotNull);
    expect(ReportEditDraft.validateDescription('x' * 4001), isNotNull);
    expect(ReportEditDraft.validateLocation('x' * 301), isNotNull);
    expect(ReportEditDraft.validateLocation(''), isNull);
    expect(draft.toUpdateData().keys.toSet(),
        {'title', 'description', 'location', 'category', 'priority'});
    expect(draft.validationError, isNull);
  });

  test('invalid content never reaches the write', () async {
    final db = FakeFirebaseFirestore();
    final ref = db.collection('reports').doc('r');
    await ref.set(report());
    for (final value in [
      const ReportEditDraft(
          title: ' ',
          description: 'Description',
          location: '',
          category: 'obras',
          priority: 'alta'),
      const ReportEditDraft(
          title: 'Title',
          description: 'Description',
          location: '',
          category: 'invalid',
          priority: 'alta'),
      const ReportEditDraft(
          title: 'Title',
          description: 'Description',
          location: '',
          category: 'obras',
          priority: 'invalid'),
    ]) {
      await expectLater(
        ReportContentEditor(firestore: db, currentUserId: () => 'neighbor-a')
            .save('r', value),
        throwsA(isA<FirebaseException>()
            .having((e) => e.code, 'code', 'invalid-argument')),
      );
      expect((await ref.get()).data(), report());
    }
  });
}
