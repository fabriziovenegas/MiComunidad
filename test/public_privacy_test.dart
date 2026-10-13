import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/screens/auth/request_status_screen.dart';
import 'package:micomunidad/utils/email_privacy.dart';

// All identifiers and addresses below are fictional test data.
void main() {
  test('el correo se oculta y no se vuelve a enmascarar incorrectamente', () {
    for (final entry in <Object?, String>{
      'holaadios@example.com': 'ho****@***.com',
      'ab@example.com': 'a****@***.com',
      'a@example.com': '****@***.com',
      '  hello@example.co.uk  ': 'he****@***.uk',
      'ho****@***.com': 'ho****@***.com',
      'a****@***.com': 'a****@***.com',
      null: '',
      '': '',
      'invalid': '',
      'a@@example.com': '',
    }.entries) {
      expect(maskPublicEmail(entry.key), entry.value);
    }
  });

  testWidgets(
      'request-status no muestra el correo completo de una respuesta antigua',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: RequestStatusScreen(
        initialDni: '00000000',
        initialRequest: {
          'name': 'Vecino de prueba',
          'status': 'aprobado',
          'email': 'holaadios@example.com',
          'createdAt': '2026-10-04T12:00:00Z',
        },
      ),
    ));
    expect(find.textContaining('ho****@***.com'), findsOneWidget);
    expect(find.textContaining('holaadios@example.com'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
