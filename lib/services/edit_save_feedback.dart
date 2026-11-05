import 'dart:async';
import 'package:firebase_core/firebase_core.dart';

class EditConnectionRequired implements Exception {
  const EditConnectionRequired();
}

/// Never expose native exception text; preserve only known business messages.
String editSaveErrorMessage(Object error) {
  if (error is EditConnectionRequired) {
    return 'Necesitas conexión para guardar los cambios';
  }
  if (error is FirebaseException) {
    const safeMessages = {
      'El DNI ya pertenece a otra cuenta.',
      'Ya existe una solicitud pendiente para ese DNI.',
      'El correo ya está registrado.',
      'El correo ya pertenece a otra cuenta.',
      'Ya existe una solicitud pendiente para ese correo.',
      'Ya existe una solicitud pendiente o una cuenta registrada con este correo. Consulta tu solicitud o recupera tu contraseña si ya tienes una cuenta.',
      'Selecciona una opción válida para el tiempo en la comunidad.',
      'Revisa el nombre, DNI, teléfono y correo del perfil.',
      'Revisa los datos de la comunidad y su longitud.',
      'El perfil cambió. Vuelve a cargarlo e inténtalo de nuevo.',
      'No se completó la actualización. Reintenta guardar el perfil para sincronizar la cuenta.',
    };
    if (safeMessages.contains(error.message)) return error.message!;
    switch (error.code) {
      case 'unavailable':
      case 'network-request-failed':
        return 'No se pudo conectar. Revisa tu conexión e inténtalo nuevamente.';
      case 'deadline-exceeded':
        return 'No se pudo confirmar el guardado. Revisa los datos antes de reintentar.';
      case 'permission-denied':
      case 'unauthenticated':
        return 'Tu cuenta no tiene permiso para guardar estos cambios. Revisa tu acceso.';
      case 'already-exists':
        return 'El DNI o correo ya está asociado a otra cuenta o solicitud pendiente.';
      case 'invalid-argument':
        return 'Revisa los datos ingresados e inténtalo nuevamente.';
      case 'not-found':
        return 'El registro ya no está disponible. Vuelve a abrirlo.';
    }
  }
  if (error is TimeoutException) {
    return 'No se pudo confirmar el guardado. Revisa los datos antes de reintentar.';
  }
  return 'No se pudieron guardar los cambios. Lo escrito se conserva; inténtalo nuevamente.';
}
