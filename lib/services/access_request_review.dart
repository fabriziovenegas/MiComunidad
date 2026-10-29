import 'package:cloud_functions/cloud_functions.dart';

bool canReviewAccessRequest({required bool isAdmin, required String status}) =>
    isAdmin && status == 'pendiente';

String accessRequestReviewErrorMessage(
  Object error, {
  required bool approve,
  required String status,
}) {
  if (error is FirebaseFunctionsException) {
    if (error.code == 'already-exists') {
      final message = error.message?.trim();
      return message != null && message.isNotEmpty
          ? message
          : 'Ya existe una cuenta de Firebase Authentication con este correo. La solicitud requiere revisión y no se ha aprobado.';
    }
    if (error.code == 'failed-precondition') {
      return status == 'rechazado' && approve
          ? 'Esta solicitud fue rechazada. Para continuar, debe enviarse una nueva solicitud de ingreso.'
          : 'Esta solicitud ya fue revisada. Actualiza la lista.';
    }
  }
  return 'No se pudo completar la acción';
}

enum AccessRequestReviewResult {
  approvedEmailSent,
  approvedEmailFailed,
  rejected;

  String get message => switch (this) {
        approvedEmailSent =>
          'Vecino aprobado y cuenta creada. Se ha enviado un correo para establecer su contraseña.',
        approvedEmailFailed =>
          'Vecino aprobado y cuenta creada, pero no se pudo enviar el correo. Puede solicitar un nuevo enlace desde «Recuperar contraseña».',
        rejected => 'Solicitud rechazada.',
      };
}

/// Approval and email delivery are separate outcomes. An accepted send does not
/// guarantee delivery to the recipient's inbox.
Future<AccessRequestReviewResult> reviewAccessRequestWithEmail({
  required bool approve,
  required Future<void> Function() review,
  required Future<void> Function() sendEmail,
}) async {
  // Keep review failures in the existing screen's error handling. Never send a
  // password email before the backend confirms account creation.
  await review();
  if (!approve) return AccessRequestReviewResult.rejected;
  try {
    await sendEmail();
    return AccessRequestReviewResult.approvedEmailSent;
  } catch (_) {
    // Approval already succeeded. Do not report an approval failure or retry it.
    return AccessRequestReviewResult.approvedEmailFailed;
  }
}
