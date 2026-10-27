import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/screens/auth/request_status_screen.dart';
import 'package:micomunidad/utils/email_privacy.dart';

// All identifiers and addresses below are fictional test data.
void main() {
  test('la máscara coincide con los casos compartidos del backend', () {
    final cases = jsonDecode(
            File('test/fixtures/public_email_masks.json').readAsStringSync())
        as List;
    for (final pair in cases) {
      expect(maskPublicEmail(pair[0]), pair[1]);
      expect(maskPublicEmail(pair[1]), pair[1]);
    }
  });

  for (final entry in {
    'pendiente': 'En revisión',
    'aprobado': 'Aprobado',
    'rechazado': 'Rechazado',
    'retirado': 'Acceso retirado',
  }.entries) {
    testWidgets(
        'consulta ${entry.key} muestra solo estado, fecha y correo oculto',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: RequestStatusScreen(
          initialDni: '00000000',
          initialRequest: {
            'name': 'Nombre privado ficticio',
            'dni': '00000000',
            'status': entry.key,
            'email': 'fabrizio@example.com',
            'rejectionReason': 'Motivo privado ficticio',
            'createdAt': '2026-10-04T12:00:00Z',
          },
        ),
      ));
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('Fecha de envío'), findsOneWidget);
      expect(find.text('Correo electrónico'), findsOneWidget);
      expect(find.text('fa*****o@example.com'), findsOneWidget);
      expect(find.textContaining('fabrizio@example.com'), findsNothing);
      expect(find.textContaining('Nombre privado ficticio'), findsNothing);
      expect(find.textContaining('Motivo privado ficticio'), findsNothing);
      expect(find.text('Solicitante'), findsNothing);
      expect(find.text('DNI registrado'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('la respuesta mínima no necesita nombre, DNI ni motivo',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: RequestStatusScreen(initialRequest: {
      'status': 'aprobado',
      'email': 'fa*****o@example.com',
      'createdAt': '2026-10-04T12:00:00Z',
    })));
    expect(find.text('fa*****o@example.com'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Consultar estado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
