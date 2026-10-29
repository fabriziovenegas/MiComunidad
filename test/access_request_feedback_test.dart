import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/services/access_request_feedback.dart';

void main() {
  const expected =
      'No pudimos procesar tu solicitud porque algunos de los datos ingresados ya están asociados a una cuenta activa. Revisa la información o comunícate con un administrador.';
  test('an approved DNI precheck uses the exact generic account message', () {
    expect(activeAccountConflictFeedback(status: 'aprobado'), expected);
  });
  test('a backend active-account conflict uses the same exact message', () {
    expect(
        activeAccountConflictFeedback(
            code: 'already-exists',
            details: {'reason': 'active-account-conflict'}),
        expected);
  });
  test('pending requests and normal validation errors keep their own messages',
      () {
    for (final status in ['pendiente', 'rechazado', 'retirado']) {
      expect(activeAccountConflictFeedback(status: status), isNull);
    }
    for (final code in [
      'invalid-argument',
      'unavailable',
      'permission-denied'
    ]) {
      expect(activeAccountConflictFeedback(code: code), isNull);
    }
    expect(activeAccountConflictFeedback(code: 'already-exists'), isNull);
    expect(
        activeAccountConflictFeedback(
            code: 'already-exists', details: {'reason': 'other'}),
        isNull);
  });
}
