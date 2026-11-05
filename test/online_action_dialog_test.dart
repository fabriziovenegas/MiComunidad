import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/widgets/online_action_dialog.dart';
import 'package:micomunidad/widgets/report_status_dialog.dart';
import 'package:micomunidad/widgets/upload_error_notice.dart';

void main() {
  tearDown(dismissUploadError);
  for (final kind in [
    'archive',
    'delete-photo',
    'delete-document',
    'delete-event',
    'remove-member',
    'change-role',
    'delete-map-point',
    'restore-project',
    'delete-comment'
  ]) {
    final slowMessage = switch (kind) {
      'delete-event' =>
        'La eliminación de la actividad está tardando. Verifica tu conexión.',
      'remove-member' =>
        'La retirada de acceso está tardando. Verifica tu conexión.',
      'change-role' => 'El cambio de rol está tardando. Verifica tu conexión.',
      'restore-project' =>
        'La restauración del proyecto está tardando. Verifica tu conexión.',
      'delete-comment' =>
        'La eliminación del comentario está tardando. Verifica tu conexión.',
      'delete-map-point' =>
        'La eliminación del punto del mapa está tardando. Verifica tu conexión.',
      _ => 'La operación está tardando. Espera un momento',
    };
    Future<void> open(WidgetTester tester, Future<void> Function() action,
        {required Future<bool> Function() offline}) async {
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showOnlineActionConfirmation(context,
                          actionKey: kind,
                          title: 'Confirm',
                          question: 'Fictitious content',
                          confirmLabel: 'Continue',
                          successMessage: 'Confirmed',
                          slowMessage: slowMessage,
                          action: action,
                          isOffline: offline),
                      child: const Text('Open'))))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('$kind offline retains dialog and permits reconnect retry',
        (tester) async {
      var offline = true;
      var calls = 0;
      await open(tester, () async {
        calls++;
      }, offline: () async => offline);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.text('Necesitas conexión para realizar esta acción'),
          findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      offline = false;
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });
    testWidgets(
        '$kind slow shows amber, closes safely and blocks duplicate reopen',
        (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      await open(tester, () {
        calls++;
        return pending.future;
      }, offline: () async => false);
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.tap(find.text('Esperando confirmación…'));
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(const ValueKey('save-warning-notice')), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text(slowMessage), findsOneWidget);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Esta operación sigue en curso. Espera un momento.'),
          findsOneWidget);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Confirmed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('$kind backend error never confirms and allows retry',
        (tester) async {
      var calls = 0;
      await open(tester, () async {
        if (++calls == 1) {
          throw FirebaseException(
              plugin: 'cloud_functions',
              code: 'permission-denied',
              message: 'java.private detail');
        }
      }, offline: () async => false);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Confirmed'), findsNothing);
      expect(find.textContaining('java.private'), findsNothing);
      expect(find.text('Tu cuenta no tiene permiso para realizar esta acción.'),
          findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Confirmed'), findsOneWidget);
    });
    testWidgets('$kind cancel never calls backend', (tester) async {
      var calls = 0;
      await open(tester, () async {
        calls++;
      }, offline: () async => false);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(calls, 0);
    });
  }
  testWidgets(
      'status offline preserves selection; after 5s can close without duplicate write',
      (tester) async {
    var offline = true;
    var calls = 0;
    final pending = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showDialog<String>(
                        context: context,
                        builder: (_) => ReportStatusDialog(
                            initialStatus: 'resuelto',
                            actionKey: 'status-test',
                            isOffline: () => Future.value(offline),
                            onSave: (status) {
                              expect(status, 'resuelto');
                              calls++;
                              return pending.future;
                            })),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Resuelto'), findsOneWidget);
    expect(find.text('Necesitas conexión para realizar esta acción'),
        findsOneWidget);
    offline = false;
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('La operación está tardando. Espera un momento'),
        findsOneWidget);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    pending.complete();
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Estado actualizado.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
