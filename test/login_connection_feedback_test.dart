import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/screens/auth/login_screen.dart';
import 'package:micomunidad/services/auth_service.dart';
import 'package:micomunidad/widgets/upload_error_notice.dart';

void main() {
  tearDown(dismissUploadError);
  Future<void> open(WidgetTester tester, Future<void> Function() action,
      {required Future<bool> Function() offline}) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => LoginScreen(
                                isOffline: offline,
                                signIn: ({required email, required password}) {
                                  expect(email, 'fictional@example.com');
                                  expect(password, 'fictitious-password');
                                  return action();
                                }))),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextFormField).at(0), 'fictional@example.com');
    await tester.enterText(
        find.byType(TextFormField).at(1), 'fictitious-password');
    await tester.ensureVisible(find.text('Iniciar sesión'));
  }

  testWidgets(
      'offline login does not contact Auth and preserves credentials for retry',
      (tester) async {
    var offline = true, calls = 0;
    await open(tester, () async {
      calls++;
    }, offline: () => Future.value(offline));
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Necesitas conexión para iniciar sesión'), findsOneWidget);
    expect(find.byKey(const ValueKey('upload-error-notice')), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(1))
            .controller!
            .text,
        'fictitious-password');
    offline = false;
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byKey(const ValueKey('save-warning-notice')), findsNothing);
  });
  testWidgets(
      'slow login warns only at 5s and blocks button and keyboard repeats',
      (tester) async {
    final gate = Completer<void>();
    var calls = 0;
    await open(tester, () {
      calls++;
      return gate.future;
    }, offline: () async => false);
    // Capture the real keyboard callback, then exercise it before the next frame too.
    final fields = find.byType(TextField);
    final enter = tester.widget<TextField>(fields.at(1)).onSubmitted!;
    await tester.tap(find.text('Iniciar sesión'));
    enter('fictitious-password');
    enter('fictitious-password');
    await tester.pump();
    await tester.tap(find.text('Ingresando…'));
    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(const ValueKey('save-warning-notice')), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('El inicio de sesión está tardando. Verifica tu conexión'),
        findsOneWidget);
    expect(calls, 1);
    expect(find.byType(LoginScreen), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byKey(const ValueKey('save-warning-notice')), findsNothing);
  });
  for (final entry in {
    'invalid-credential': 'Correo o contraseña incorrectos.',
    'network-request-failed': 'No hay conexión. Revisa tu internet.',
    'too-many-requests': 'Demasiados intentos. Inténtalo más tarde.',
  }.entries) {
    testWidgets('${entry.key} keeps existing friendly error and permits retry',
        (tester) async {
      var calls = 0;
      await open(tester, () async {
        if (++calls == 1) {
          throw FirebaseAuthException(
              code: entry.key, message: 'java private detail');
        }
      }, offline: () async => false);
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(find.textContaining('java private'), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.byType(LoginScreen), findsNothing);
    });
  }
  testWidgets('unapproved account keeps existing access error', (tester) async {
    await open(tester, () async {
      throw const AuthFlowException('La solicitud todavía está en revisión.');
    }, offline: () async => false);
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('La solicitud todavía está en revisión.'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
  testWidgets('invalid form does not call connection checker or authentication',
      (tester) async {
    var checks = 0, calls = 0;
    await open(tester, () async {
      calls++;
    }, offline: () async {
      checks++;
      return false;
    });
    await tester.enterText(find.byType(TextFormField).at(0), 'invalid');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(checks, 0);
    expect(find.text('Ingresa un correo válido.'), findsOneWidget);
  });
  testWidgets('leaving during login never updates disposed state or resends',
      (tester) async {
    final gate = Completer<void>();
    var calls = 0;
    await open(tester, () {
      calls++;
      return gate.future;
    }, offline: () async => false);
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    expect(find.byKey(const ValueKey('save-warning-notice')), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
}
