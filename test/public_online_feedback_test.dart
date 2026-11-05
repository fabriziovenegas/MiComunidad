import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/screens/auth/login_screen.dart';
import 'package:micomunidad/screens/auth/signup_screen.dart';
import 'package:micomunidad/screens/auth/request_status_screen.dart';
import 'package:micomunidad/services/auth_service.dart';
import 'package:micomunidad/widgets/password_reset_dialog.dart';
import 'package:micomunidad/widgets/upload_error_notice.dart';
import 'access_request_documents_test.dart' show sample, choose;

const resetMessage =
    'Si el correo está asociado a una cuenta, recibirás un enlace para restablecer tu contraseña.';
void main() {
  tearDown(dismissUploadError);
  Future<void> reset(WidgetTester tester, Future<void> Function(String) send,
      {required Future<bool> Function() offline}) async {
    await tester.pumpWidget(MaterialApp(
        home: LoginScreen(sendResetEmail: send, isOffline: offline)));
    await tester.ensureVisible(find.text('¿Olvidaste tu contraseña?'));
    await tester.tap(find.text('¿Olvidaste tu contraseña?'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: find.byType(PasswordResetDialog),
            matching: find.byType(TextFormField)),
        'fictional@example.com');
  }

  testWidgets(
      'reset offline keeps email, sends nothing, and retries after reconnect',
      (tester) async {
    var offline = true, calls = 0;
    await reset(tester, (email) async {
      calls++;
      expect(email, 'fictional@example.com');
    }, offline: () => Future.value(offline));
    await tester.tap(find.text('Enviar enlace'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Necesitas conexión para recuperar tu contraseña'),
        findsOneWidget);
    expect(find.text('fictional@example.com'), findsOneWidget);
    expect(find.text(resetMessage), findsNothing);
    offline = false;
    await tester.tap(find.text('Enviar enlace'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(PasswordResetDialog), findsNothing);
    expect(find.text(resetMessage), findsOneWidget);
    expect(find.byKey(const ValueKey('upload-error-notice')), findsNothing);
  });
  testWidgets(
      'reset slow amber only at 5s, duplicate taps and enter do not resend',
      (tester) async {
    final gate = Completer<void>();
    var calls = 0;
    await reset(tester, (_) {
      calls++;
      return gate.future;
    }, offline: () async => false);
    await tester.tap(find.text('Enviar enlace'));
    await tester.pump();
    await tester.tap(find.text('Enviando…'));
    tester
        .widget<TextField>(find.descendant(
            of: find.byType(PasswordResetDialog),
            matching: find.byType(TextField)))
        .onSubmitted
        ?.call('fictional@example.com');
    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(const ValueKey('save-warning-notice')), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(
        find.text('El envío del enlace está tardando. Verifica tu conexión.'),
        findsOneWidget);
    expect(find.text(resetMessage), findsNothing);
    expect(calls, 1);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text(resetMessage), findsOneWidget);
    expect(find.byKey(const ValueKey('save-warning-notice')), findsNothing);
  });
  testWidgets(
      'reset backend failure preserves email, hides technical errors and allows retry',
      (tester) async {
    var calls = 0;
    await reset(tester, (_) async {
      if (++calls == 1) throw StateError('private technical detail');
    }, offline: () async => false);
    await tester.tap(find.text('Enviar enlace'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'No se pudo enviar el enlace. Verifica el correo y la conexión.'),
        findsOneWidget);
    expect(find.text(resetMessage), findsNothing);
    expect(find.textContaining('private technical'), findsNothing);
    await tester.tap(find.text('Enviar enlace'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
  testWidgets('reset invalid email never sends', (tester) async {
    var calls = 0;
    await reset(tester, (_) async {
      calls++;
    }, offline: () async => false);
    await tester.enterText(
        find.descendant(
            of: find.byType(PasswordResetDialog),
            matching: find.byType(TextFormField)),
        'invalid');
    await tester.tap(find.text('Enviar enlace'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Ingresa un correo válido.'), findsOneWidget);
  });

  for (final delayed in [false, true]) {
    testWidgets('DNI offline, retry and result ($delayed)', (tester) async {
      var offline = true, calls = 0;
      final gate = Completer<Map<String, dynamic>?>();
      await tester.pumpWidget(MaterialApp(
          home: RequestStatusScreen(
              initialDni: '00000001',
              isOffline: () => Future.value(offline),
              findRequest: (dni) {
                calls++;
                expect(dni, '00000001');
                return gate.future;
              })));
      await tester.tap(find.text('Consultar estado'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(
          find.text(
              'Necesitas conexión para consultar el estado de tu solicitud'),
          findsOneWidget);
      offline = false;
      await tester.tap(find.text('Consultar estado'));
      await tester.pump();
      await tester.tap(find.text('Consultando…'));
      if (delayed) {
        await tester.pump(const Duration(seconds: 5));
        await tester.pump();
        expect(find.text('La consulta está tardando. Verifica tu conexión.'),
            findsOneWidget);
      }
      expect(calls, 1);
      gate.complete({
        'status': 'pendiente',
        'emailMasked': 'fi*****l@example.com',
        'createdAt': '2026-11-04T10:00:00Z'
      });
      await tester.pumpAndSettle();
      expect(find.text('En revisión'), findsOneWidget);
      expect(find.byKey(const ValueKey('save-warning-notice')), findsNothing);
    });
  }
  testWidgets(
      'DNI not found and backend failure do not invent an application state',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: RequestStatusScreen(
            initialDni: '00000001',
            isOffline: () async => false,
            findRequest: (_) async {
              if (++calls == 1) return null;
              throw StateError('private');
            })));
    await tester.tap(find.text('Consultar estado'));
    await tester.pumpAndSettle();
    expect(
        find.text('No encontramos una solicitud con ese DNI.'), findsOneWidget);
    await tester.tap(find.text('Consultar estado'));
    await tester.pumpAndSettle();
    expect(find.text('No se pudo consultar el estado. Inténtalo nuevamente.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('upload-error-notice')), findsOneWidget);
  });

  for (final fail in [false, true]) {
    testWidgets(
        'signup offline retains files, blocks duplicates and handles ${fail ? 'failure' : 'success'}',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(414, 1600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var offline = true, calls = 0;
      final gate = Completer<String>();
      await tester.pumpWidget(MaterialApp(
          routes: {
            '/request-success': (_) =>
                const Scaffold(body: Text('Confirmed request'))
          },
          home: SignupScreen(
              isOffline: () => Future.value(offline),
              pickDocument: (_) async => sample('fictional.pdf'),
              submitRequest: (
                  {required name,
                  required dni,
                  required phone,
                  required email,
                  required address,
                  required timeLivingHere,
                  required reason,
                  required identityDocuments}) {
                calls++;
                expect(identityDocuments.length, 1);
                return gate.future;
              })));
      final fields = find.byType(TextFormField);
      const values = [
        'Fictional Applicant',
        '00000001',
        '000000001',
        'fictional@example.com',
        'Fictional address',
        'Fictional reason'
      ];
      for (var i = 0; i < values.length; i++) {
        await tester.ensureVisible(fields.at(i));
        await tester.enterText(fields.at(i), values[i]);
      }
      final time = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(time);
      await tester.tap(time);
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 a 5 años').last);
      await tester.pumpAndSettle();
      await choose(tester, 'Seleccionar archivo');
      await tester.ensureVisible(find.text('Enviar solicitud'));
      await tester.tap(find.text('Enviar solicitud'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(
          find.text('Necesitas conexión para enviar tu solicitud de ingreso'),
          findsOneWidget);
      expect(find.text('1 de 3'), findsOneWidget);
      offline = false;
      await tester.tap(find.text('Enviar solicitud'));
      await tester.pump();
      await tester.tap(find.text('Enviando…'));
      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(const ValueKey('save-warning-notice')), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(
          find.text(
              'El envío de la solicitud está tardando. Verifica tu conexión y mantén la app abierta.'),
          findsOneWidget);
      expect(calls, 1);
      if (fail) {
        gate.completeError(
            const AuthFlowException('Fallo ficticio de subida.'));
      } else {
        gate.complete('fictional-request');
      }
      await tester.pumpAndSettle();
      if (fail) {
        expect(find.text('Fallo ficticio de subida.'), findsOneWidget);
        expect(find.text('1 de 3'), findsOneWidget);
        expect(tester.widget<TextFormField>(fields.first).controller!.text,
            values.first);
      } else {
        expect(find.text('Confirmed request'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
