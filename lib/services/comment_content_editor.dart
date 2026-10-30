import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/report_edit.dart';

class CommentContentEditor {
  const CommentContentEditor(
      {required this.firestore, required this.currentUserId});
  final FirebaseFirestore firestore;
  final String? Function() currentUserId;

  Future<void> save(
      {required String collection,
      required String documentId,
      required String commentId,
      required String originalText,
      required String text}) async {
    final value = text.trim();
    if (!['reports', 'projects', 'events'].contains(collection) ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(documentId) ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(commentId) ||
        value.isEmpty ||
        text.length > 1000) {
      throw ArgumentError('Escribe entre 1 y 1000 caracteres.');
    }
    final uid = currentUserId();
    if (uid == null || uid.isEmpty) {
      throw StateError('Inicia sesión para editar.');
    }
    final parent = firestore.collection(collection).doc(documentId);
    final comment = parent.collection('comments').doc(commentId);
    final failure = await firestore.runTransaction<Object?>((tx) async {
      try {
        final profile =
            (await tx.get(firestore.collection('users').doc(uid))).data();
        final content = await tx.get(parent);
        final existing = await tx.get(comment);
        final data = content.data();
        final allowed = profile?['approvalStatus'] == 'aprobado' &&
            ['vecino', 'admin'].contains(profile?['role']) &&
            profile?['profileWithdrawalInProgress'] != true;
        if (currentUserId() != uid ||
            !allowed ||
            !content.exists ||
            data?['deletionInProgress'] == true ||
            existing.data()?['authorId'] != uid ||
            (collection == 'projects' && data?['isTrashed'] != false) ||
            (collection == 'reports' && !reportAcceptsComments(data!))) {
          return StateError('Este comentario ya no permite guardar cambios.');
        }
        if (existing.data()?['text'] == value) return null;
        if (existing.data()?['text'] != originalText) {
          return StateError(
              'El comentario cambió. Ciérralo y vuelve a abrirlo antes de editar.');
        }
        tx.update(comment,
            {'text': value, 'updatedAt': FieldValue.serverTimestamp()});
        return null;
      } catch (error) {
        return error;
      }
    });
    if (failure != null) throw failure;
  }
}
