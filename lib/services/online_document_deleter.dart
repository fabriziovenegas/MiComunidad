import 'package:cloud_firestore/cloud_firestore.dart';

/// Deletion stages must reach the server, never become offline queued writes.
Future<void> deleteDocumentsOnline(FirebaseFirestore firestore,
    Iterable<DocumentReference<Map<String, dynamic>>> references) async {
  final documents = references.toList(growable: false);
  if (documents.isEmpty) return;
  final failure = await firestore.runTransaction<Object?>((transaction) async {
    try {
      final snapshots = await Future.wait(documents.map(transaction.get));
      for (var i = 0; i < documents.length; i++) {
        if (snapshots[i].exists) transaction.delete(documents[i]);
      }
      return null;
    } catch (error) {
      return error;
    }
  });
  if (failure != null) throw failure;
}
