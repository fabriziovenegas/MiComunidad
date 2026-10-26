import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';

enum PendingSendState { sent, queued, blocked }

class PendingSendResult {
  const PendingSendResult(this.state, {this.reason});
  final PendingSendState state;
  final String? reason;
}

bool pendingFailureIsTemporary(Object error) =>
    error is SocketException ||
    error is TimeoutException ||
    (error is FirebaseException &&
        const {
          'unavailable',
          'deadline-exceeded',
          'network-request-failed',
          'retry-limit-exceeded',
          'unknown',
          'canceled',
          'aborted',
        }.contains(error.code));

String pendingFailureReason(Object error) {
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' ||
      'unauthorized' =>
        'No tienes permiso o este contenido ya no admite cambios.',
      'unauthenticated' => 'Inicia sesión con la cuenta que hizo el envío.',
      'not-found' ||
      'object-not-found' =>
        'El contenido ya no está disponible.',
      'resource-exhausted' ||
      'quota-exceeded' =>
        'El servicio alcanzó su límite. Inténtalo más tarde.',
      _ => 'No se pudo completar el envío. La copia sigue guardada.',
    };
  }
  return error is FileSystemException
      ? 'No se pudo leer el archivo guardado en este dispositivo.'
      : 'No se pudo completar el envío. La copia sigue guardada.';
}
