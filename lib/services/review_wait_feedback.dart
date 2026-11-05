import 'dart:async';

/// This is a notice timer, not a timeout: never cancel or resend a review.
Future<T> waitForReview<T>({
  required Future<T> Function() action,
  required void Function() onSlow,
}) async {
  final timer = Timer(const Duration(seconds: 5), onSlow);
  try {
    return await action();
  } finally {
    timer.cancel();
  }
}

String reviewWaitingMessage({required bool approve, required bool isReport}) {
  if (isReport) {
    return '${approve ? 'Aprobación' : 'Rechazo'} pendiente de envío. '
        'Se enviará con conexión y la app abierta.';
  }
  return '${approve ? 'La aprobación' : 'El rechazo'} está tardando. '
      'Mantén la app abierta y espera la confirmación.';
}
