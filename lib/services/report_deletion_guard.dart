import 'package:cloud_firestore/cloud_firestore.dart';

/// Closes the parent to new comments before any dependency is removed.
/// A failed deletion keeps this marker so an administrator can safely retry.
class ReportDeletionGuard {
  const ReportDeletionGuard({
    required this.firestore,
    required this.currentUserId,
  });

  final FirebaseFirestore firestore;
  final String? Function() currentUserId;

  Future<void> begin(String reportId) async {
    final uid = currentUserId();
    if (uid == null || uid.isEmpty) {
      throw FirebaseException(
          plugin: 'cloud_firestore', code: 'unauthenticated');
    }
    final reference = firestore.collection('reports').doc(reportId);
    await firestore.runTransaction((transaction) async {
      final profile =
          await transaction.get(firestore.collection('users').doc(uid));
      final report = await transaction.get(reference);
      if (!report.exists) {
        throw FirebaseException(plugin: 'cloud_firestore', code: 'not-found');
      }
      final data = report.data()!;
      final completed = data['moderationStatus'] == 'rechazado' ||
          (data['moderationStatus'] == 'aprobado' &&
              const ['resuelto', 'rechazado'].contains(data['status']));
      if (currentUserId() != uid ||
          profile.data()?['role'] != 'admin' ||
          profile.data()?['approvalStatus'] != 'aprobado' ||
          !completed) {
        throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
            message:
                'Solo un administrador puede eliminar reportes resueltos o rechazados.');
      }
      transaction.update(reference, {
        'deletionInProgress': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
