import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/report_edit.dart';

class ReportContentEditor {
  const ReportContentEditor({
    required this.firestore,
    required this.currentUserId,
  });

  final FirebaseFirestore firestore;
  final String? Function() currentUserId;

  Future<void> save(String reportId, ReportEditDraft draft) async {
    final userId = currentUserId();
    if (userId == null || userId.isEmpty) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unauthenticated',
        message: 'Debes iniciar sesión para editar tu reporte.',
      );
    }
    final validationError = draft.validationError;
    if (validationError != null) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'invalid-argument',
        message: validationError,
      );
    }

    final reference = firestore.collection('reports').doc(reportId);
    // A transaction checks the latest state and avoids a stale edit racing
    // with moderation or resolution. Firestore rules enforce ownership too.
    await firestore.runTransaction((transaction) async {
      final document = await transaction.get(reference);
      if (!document.exists) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'not-found',
          message: 'El reporte ya no existe.',
        );
      }
      final data = document.data()!;
      var editable = canEditOwnActiveReport(data, userId);
      if (!editable &&
          data['createdBy'] == userId &&
          reportIsApprovedResolved(data)) {
        // Do not trust an interface flag for the resolved-report exception.
        // Read the approved administrator role in the same transaction.
        final profile =
            await transaction.get(firestore.collection('users').doc(userId));
        editable = profile.data()?['role'] == 'admin' &&
            profile.data()?['approvalStatus'] == 'aprobado';
      }
      if (currentUserId() != userId || !editable) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message: 'Este reporte ya no permite editar su contenido.',
        );
      }
      transaction.update(reference, {
        ...draft.toUpdateData(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
