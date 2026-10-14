import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/report_edit.dart';

class ReportCommentWriter {
  const ReportCommentWriter({
    required this.firestore,
    required this.currentUserId,
  });

  final FirebaseFirestore firestore;
  final String? Function() currentUserId;

  Future<void> add({
    required String reportId,
    required String text,
    required String authorName,
  }) async {
    final uid = currentUserId();
    if (uid == null || uid.isEmpty) {
      throw FirebaseException(
          plugin: 'cloud_firestore', code: 'unauthenticated');
    }
    final value = text.trim();
    if (value.isEmpty || value.length > 1000) {
      throw ArgumentError('Escribe entre 1 y 1000 caracteres.');
    }
    final parent = firestore.collection('reports').doc(reportId);
    final comment = parent.collection('comments').doc();
    await firestore.runTransaction((transaction) async {
      final profile =
          await transaction.get(firestore.collection('users').doc(uid));
      final report = await transaction.get(parent);
      final allowed = profile.data()?['approvalStatus'] == 'aprobado' &&
          const ['vecino', 'admin'].contains(profile.data()?['role']);
      if (currentUserId() != uid ||
          !allowed ||
          !report.exists ||
          !reportAcceptsComments(report.data()!)) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message: 'El reporte ya no admite comentarios o está en eliminación.',
        );
      }
      transaction.set(comment, {
        'text': value,
        'authorId': uid,
        'authorName': authorName,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
