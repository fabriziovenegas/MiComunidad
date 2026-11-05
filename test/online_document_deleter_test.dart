import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/services/online_document_deleter.dart';
import 'package:micomunidad/services/online_admin_action_writer.dart';
import 'online_admin_action_writer_test.dart' show DisconnectedDatabase;

void main() {
  test('deletes only requested records, safely retries missing records',
      () async {
    final db = FakeFirebaseFirestore();
    for (final path in [
      'projects/p/photos/a',
      'projects/p/photos/b',
      'projects/other/photos/keep'
    ]) {
      await db.doc(path).set({'name': 'Fictitious'});
    }
    final refs =
        ['projects/p/photos/a', 'projects/p/photos/b'].map(db.doc).toList();
    await deleteDocumentsOnline(db, refs);
    await deleteDocumentsOnline(db, refs);
    for (final ref in refs) {
      expect((await ref.get()).exists, false);
    }
    expect((await db.doc('projects/other/photos/keep').get()).exists, true);
  });
  test('connection loss does not queue deletions or alter records', () async {
    final db = DisconnectedDatabase();
    await db.doc('reports/r/comments/a').set({'text': 'keep'});
    final before = db.dump();
    await expectLater(
        deleteDocumentsOnline(db, [db.doc('reports/r/comments/a')]),
        throwsA(isA<FirebaseException>()));
    expect(db.dump(), before);
  });
  for (final role in ['admin', 'vecino']) {
    test('map deletion checks approved admin, role $role', () async {
      final db = FakeFirebaseFirestore();
      await db.doc('users/u').set({'role': role, 'approvalStatus': 'aprobado'});
      await db.doc('mapPoints/p').set({'title': 'Fictitious'});
      final writer =
          OnlineAdminActionWriter(firestore: db, currentUserId: () => 'u');
      if (role == 'admin') {
        await writer.deleteMapPoint('p');
        expect((await db.doc('mapPoints/p').get()).exists, false);
      } else {
        await expectLater(
            writer.deleteMapPoint('p'), throwsA(isA<FirebaseException>()));
        expect((await db.doc('mapPoints/p').get()).exists, true);
      }
    });
  }
}
