import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/widgets/form_submission_guard.dart';
import 'package:micomunidad/widgets/upload_error_notice.dart';

Future<void> openForm(WidgetTester tester, Future<void> Function() send,
    {bool Function()? validate,
    ValueChanged<bool?>? closed,
    Duration? slowAfter,
    String Function(Object)? errorMessage}) async {
  await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () async {
                    final result = await showDialog<bool>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => FormSubmissionGuard(
                            onSubmit: send,
                            slowAfter: slowAfter,
                            errorMessage: errorMessage,
                            validate: validate,
                            onSubmitted: (context) =>
                                Navigator.pop(context, true),
                            builder: (context, saving, submit) => AlertDialog(
                                    title: const Text('Demo form'),
                                    content: TextFormField(
                                        initialValue: 'Demo draft',
                                        enabled: !saving),
                                    actions: [
                                      TextButton(
                                          onPressed: saving &&
                                                  !FormSubmissionGuard
                                                      .isTakingLong(context)
                                              ? null
                                              : () =>
                                                  Navigator.pop(context, false),
                                          child: const Text('Cancelar')),
                                      FilledButton(
                                          onPressed: saving ? null : submit,
                                          child: Text(saving
                                              ? 'Guardando…'
                                              : 'Guardar'))
                                    ])));
                    closed?.call(result);
                  },
                  child: const Text('Open'))))));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(dismissUploadError);
  testWidgets(
      'waits for confirmation, blocks duplicate presses, outside taps, cancel and back',
      (tester) async {
    final ack = Completer<void>();
    var calls = 0;
    bool? result;
    await openForm(tester, () {
      calls++;
      return ack.future;
    }, closed: (value) => result = value);
    final save =
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed!;
    save();
    save();
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Guardando…'), findsOneWidget);
    expect(tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
        false);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancelar'))
            .onPressed,
        isNull);
    await tester.tapAt(const Offset(3, 3));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Demo form'), findsOneWidget);
    expect(result, isNull);
    ack.complete();
    await tester.pumpAndSettle();
    expect(result, true);
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets(
      'an error keeps the entered text and shows the agreed notice above the dialog',
      (tester) async {
    var calls = 0;
    await openForm(tester, () async {
      calls++;
      if (calls == 1) throw StateError('Private exception detail');
    });
    await tester.enterText(
        find.byType(TextFormField), 'Retained fictional input');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Hubo un problema con el envío. Tus datos se conservan.'),
        findsOneWidget);
    expect(find.text('Retained fictional input'), findsOneWidget);
    expect(find.textContaining('Private exception'), findsNothing);
    expect(find.byTooltip('Cerrar aviso').hitTestable(), findsOneWidget);
    expect(
        tester.widget<TextFormField>(find.byType(TextFormField)).enabled, true);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const ValueKey('upload-error-notice')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'slow save warns in amber, allows closing, never resubmits or claims success',
      (tester) async {
    final ack = Completer<void>();
    var calls = 0;
    await openForm(tester, () {
      calls++;
      return ack.future;
    }, slowAfter: const Duration(seconds: 10));
    final submit =
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed!;
    submit();
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    final notice = find.byKey(const ValueKey('save-warning-notice'));
    expect(tester.widget<Material>(notice).color, const Color(0xFFFFE6A7));
    expect(find.text('El guardado está tardando. Comprueba tu conexión'),
        findsOneWidget);
    expect(find.text('Demo draft'), findsOneWidget);
    expect(tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
        false);
    submit();
    expect(calls, 1);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancelar'))
            .onPressed,
        isNotNull);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    ack.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('offline refusal retains draft and enables retry without success',
      (tester) async {
    var calls = 0;
    await openForm(tester, () async {
      calls++;
      throw StateError('offline');
    },
        slowAfter: const Duration(seconds: 10),
        errorMessage: (_) => 'Necesitas conexión para guardar los cambios');
    await tester.enterText(
        find.byType(TextFormField), 'Unsaved fictional edit');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Necesitas conexión para guardar los cambios'),
        findsOneWidget);
    expect(find.text('Unsaved fictional edit'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    await tester.pump(const Duration(seconds: 10));
    expect(find.byKey(const ValueKey('save-warning-notice')), findsNothing);
    expect(calls, 1);
  });
  testWidgets('slow save closes only after acknowledgement and removes warning',
      (tester) async {
    final ack = Completer<void>();
    await openForm(tester, () => ack.future,
        slowAfter: const Duration(seconds: 10));
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(find.byKey(const ValueKey('save-warning-notice')), findsOneWidget);
    ack.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const ValueKey('save-warning-notice')), findsNothing);
  });
  testWidgets(
      'invalid input does not submit, close the form or show a network error',
      (tester) async {
    var calls = 0;
    await openForm(tester, () async {
      calls++;
    }, validate: () => false);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Guardando…'), findsNothing);
    expect(find.byKey(const ValueKey('upload-error-notice')), findsNothing);
  });
  testWidgets('cancel remains available before submitting', (tester) async {
    var calls = 0;
    bool? result;
    await openForm(tester, () async {
      calls++;
    }, closed: (value) => result = value);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(result, false);
    expect(calls, 0);
  });
  for (final fail in [true, false]) {
    testWidgets('removing the app during a pending save is safe (error=$fail)',
        (tester) async {
      final ack = Completer<void>();
      var closed = false;
      await openForm(tester, () => ack.future, closed: (_) => closed = true);
      await tester.tap(find.text('Guardar'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      if (fail) {
        ack.completeError(StateError('Demo failure'));
      } else {
        ack.complete();
      }
      await tester.pumpAndSettle();
      expect(closed, false);
      expect(tester.takeException(), isNull);
    });
  }
}
