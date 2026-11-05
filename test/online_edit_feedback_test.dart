import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/widgets/comment_edit_dialog.dart';
import 'package:micomunidad/widgets/report_edit_dialog.dart';
import 'package:micomunidad/widgets/upload_error_notice.dart';

void main() {
  tearDown(dismissUploadError);
  for (final report in [true, false]) {
    final kind = report ? 'reporte' : 'comentario';
    Future<void> open(WidgetTester tester, Future<void> Function() action,
        {required Future<bool> Function() offline}) async {
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showDialog<bool>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => report
                              ? ReportEditDialog(
                                  data: const {
                                      'title': 'Fictitious title',
                                      'description': 'Fictitious description',
                                      'location': 'Fictitious location',
                                      'category': 'obras',
                                      'priority': 'alta',
                                      'status': 'en_proceso',
                                      'moderationStatus': 'aprobado'
                                    },
                                  actionKey: 'edit-$kind:test',
                                  isOffline: offline,
                                  onSave: (_) => action())
                              : CommentEditDialog(
                                  initialText: 'Fictitious comment',
                                  actionKey: 'edit-$kind:test',
                                  isOffline: offline,
                                  onSave: (_) => action())),
                      child: const Text('Open'))))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('$kind offline draft retained and saves after reconnect',
        (tester) async {
      var offline = true;
      var calls = 0;
      await open(tester, () async {
        calls++;
      }, offline: () => Future.value(offline));
      await tester.enterText(
          find.byType(TextFormField).first, 'Retained draft');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.text('Retained draft'), findsOneWidget);
      expect(find.text('Necesitas conexión para realizar esta acción'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('upload-error-notice')), findsOneWidget);
      offline = false;
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey('save-success-notice')), findsOneWidget);
    });
    testWidgets(
        '$kind specific amber after 5 seconds; no duplicate before success',
        (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      await open(tester, () {
        calls++;
        return pending.future;
      }, offline: () async => false);
      await tester.tap(find.text('Guardar'));
      await tester.pump();
      await tester.tap(find.text('Guardando…'));
      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(const ValueKey('save-warning-notice')), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(
          find.text(
              'El guardado del $kind está tardando. Verifica tu conexión.'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('save-success-notice')), findsNothing);
      expect(calls, 1);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey('save-success-notice')), findsOneWidget);
    });
    testWidgets('$kind failure preserves edited draft and permits retry',
        (tester) async {
      var calls = 0;
      await open(tester, () async {
        if (++calls == 1) throw StateError('fake failure');
      }, offline: () async => false);
      await tester.enterText(
          find.byType(TextFormField).first, 'Retained draft');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Retained draft'), findsOneWidget);
      expect(find.byKey(const ValueKey('upload-error-notice')), findsOneWidget);
      expect(find.byKey(const ValueKey('save-success-notice')), findsNothing);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.byType(AlertDialog), findsNothing);
    });
    testWidgets(
        '$kind close while slow then reopen does not send another write',
        (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      await open(tester, () {
        calls++;
        return pending.future;
      }, offline: () async => false);
      await tester.tap(find.text('Guardar'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Esta operación sigue en curso. Espera un momento.'),
          findsOneWidget);
      pending.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
