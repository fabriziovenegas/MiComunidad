import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/services/event_content_editor.dart';

void main() {
  late FakeFirebaseFirestore db;
  late String? uid;
  late EventContentEditor editor;
  Map<String, dynamic> fields() => {
        'title': 'Asamblea actualizada',
        'location': 'Local comunal',
        'description': 'Revisión de acuerdos',
        'eventDate': Timestamp.fromDate(DateTime(2026, 11, 20, 18, 30))
      };
  setUp(() async {
    db = FakeFirebaseFirestore();
    uid = 'admin';
    editor = EventContentEditor(firestore: db, currentUserId: () => uid);
    await db
        .doc('users/admin')
        .set({'role': 'admin', 'approvalStatus': 'aprobado'});
    await db.doc('events/activity').set({
      'title': 'Asamblea anterior',
      'location': 'Plaza',
      'description': 'Acuerdos anteriores',
      'eventDate': Timestamp.fromDate(DateTime(2021, 4, 15, 17, 5)),
      'createdBy': 'another-admin',
      'createdAt': Timestamp(1600000000, 0),
      'customField': 'Keep this'
    });
    for (final kind in ['photos', 'minutes', 'comments']) {
      await db.doc('events/activity/$kind/existing').set({'name': kind});
    }
  });
  test(
      'approved administrator updates fields while preserving identity and all related content',
      () async {
    final before = (await db.doc('events/activity').get()).data()!;
    await editor.save('activity', fields());
    final after = (await db.doc('events/activity').get()).data()!;
    for (final entry in fields().entries) {
      expect(after[entry.key], entry.value);
    }
    expect(after['createdBy'], before['createdBy']);
    expect(after['createdAt'], before['createdAt']);
    expect(after['customField'], 'Keep this');
    expect(after['updatedAt'], isA<Timestamp>());
    expect((await db.collection('events').get()).docs, hasLength(1));
    for (final kind in ['photos', 'minutes', 'comments']) {
      expect((await db.doc('events/activity/$kind/existing').get()).data(),
          {'name': kind});
    }
  });
  for (final profile in [
    {'role': 'vecino', 'approvalStatus': 'aprobado'},
    {'role': 'admin', 'approvalStatus': 'pendiente'}
  ]) {
    test('$profile cannot edit an activity', () async {
      await db.doc('users/admin').set(profile);
      final before = (await db.doc('events/activity').get()).data();
      await expectLater(
          editor.save('activity', fields()),
          throwsA(isA<FirebaseException>()
              .having((e) => e.code, 'code', 'permission-denied')));
      expect((await db.doc('events/activity').get()).data(), before);
    });
  }
  test('deleted activity is never recreated by an old edit form', () async {
    await db.doc('events/activity').delete();
    await expectLater(
        editor.save('activity', fields()),
        throwsA(isA<FirebaseException>()
            .having((e) => e.code, 'code', 'not-found')));
    expect((await db.doc('events/activity').get()).exists, false);
  });
  test('signed-out account cannot edit', () async {
    uid = null;
    await expectLater(
        editor.save('activity', fields()), throwsA(isA<FirebaseException>()));
  });
  test(
      'invalid title, date or internal-field injection is rejected before any update',
      () async {
    final before = (await db.doc('events/activity').get()).data();
    for (final payload in [
      {...fields(), 'title': ' '},
      {...fields(), 'eventDate': 'invalid'},
      {...fields(), 'createdBy': 'other'}
    ]) {
      await expectLater(editor.save('activity', payload), throwsArgumentError);
    }
    expect((await db.doc('events/activity').get()).data(), before);
  });
  test('repeating a confirmed edit does not change dates or duplicate anything',
      () async {
    await editor.save('activity', fields());
    final before = (await db.doc('events/activity').get()).data();
    await editor.save('activity', fields());
    expect((await db.doc('events/activity').get()).data(), before);
  });
}
