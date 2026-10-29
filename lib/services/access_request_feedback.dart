const activeAccountConflictMessage =
    'No pudimos procesar tu solicitud porque algunos de los datos ingresados ya están asociados a una cuenta activa. Revisa la información o comunícate con un administrador.';

String? activeAccountConflictFeedback(
    {String? status, String? code, Object? details}) {
  if (status == 'aprobado' ||
      (code == 'already-exists' &&
          details is Map &&
          details['reason'] == 'active-account-conflict')) {
    return activeAccountConflictMessage;
  }
  return null;
}
