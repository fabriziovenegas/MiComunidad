import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/utils/request_rejection_reason.dart';

void main() {
  test('los motivos históricos ausentes o inválidos tienen un texto legible',
      () {
    for (final value in [null, '', '   ', 123, <String, String>{}]) {
      expect(
          requestRejectionReason(value), 'No se indicó un motivo de rechazo.');
    }
  });

  test('el motivo conserva su contenido y elimina espacios exteriores', () {
    expect(requestRejectionReason('  Adjunta un documento legible.  '),
        'Adjunta un documento legible.');
  });

  test('los motivos históricos con tildes dañadas se pueden leer', () {
    expect(requestRejectionReason('InformaciÃ³n incompleta.'),
        'Información incompleta.');
  });
}
