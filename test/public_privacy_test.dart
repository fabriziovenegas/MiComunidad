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
        'consulta ${entry.key} oculta siempre el motivo y conserva los demás datos públicos',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: RequestStatusScreen(
          initialDni: '00000000',
          initialRequest: {
            'name': 'Nombre privado ficticio',
            'dni': '00000000',
            'status': entry.key,
            'email': 'fabrizio@example.com',
            'rejectionReason': 'El documento adjunto no es legible.',
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
      expect(find.text('Motivo del rechazo'), findsNothing);
      expect(find.text('El documento adjunto no es legible.'), findsNothing);
      const explanations = {
        'pendiente': 'El administrador está verificando tus datos.',
        'aprobado':
            'Tu cuenta fue habilitada. Revisa tu correo para establecer la contraseña.',
        'rechazado':
            'Comunícate con el administrador encargado para conocer el motivo.',
        'retirado':
            'Tu acceso anterior fue retirado. Puedes enviar una nueva solicitud de ingreso.',
      };
      expect(find.text(explanations[entry.key]!), findsOneWidget);
      expect(
          find.text(
              'Comunícate con el administrador encargado para conocer el motivo.'),
          entry.key == 'rechazado' ? findsOneWidget : findsNothing);
      expect(find.text('Solicitante'), findsNothing);
      expect(find.text('DNI registrado'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final reason in [null, '', '   ', 123]) {
    testWidgets(
        'rechazo histórico sin motivo válido muestra el mismo mensaje público: $reason',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: RequestStatusScreen(initialRequest: {
          'status': 'rechazado',
          'email': 'ap*****t@example.com',
          'createdAt': '2026-10-04T12:00:00Z',
          'rejectionReason': reason,
        }),
      ));
      expect(find.text('Rechazado'), findsOneWidget);
      expect(find.text('Motivo del rechazo'), findsNothing);
      expect(find.text('No se indicó un motivo de rechazo.'), findsNothing);
      expect(
          find.text(
              'Comunícate con el administrador encargado para conocer el motivo.'),
          findsOneWidget);
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
