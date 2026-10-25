import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/widgets/upload_error_notice.dart';

const successKey = ValueKey('save-success-notice');

void main() {
  tearDown(dismissUploadError);

  for (final message in [
    'Reporte enviado.',
    'Proyecto guardado.',
    'Actividad creada.',
  ]) {
    testWidgets('$message is visible above a closing form and navigation',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return Scaffold(
            bottomNavigationBar: NavigationBar(destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: 'Inicio'),
              NavigationDestination(icon: Icon(Icons.event), label: 'Agenda'),
            ]),
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final saved = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      content: const TextField(),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Guardar'),
                        ),
                      ],
                    ),
                  );
                  if (saved == true && context.mounted) {
                    showSuccessNotice(context, message);
                  }
                },
                child: const Text('Abrir'),
              ),
            ),
          );
        }),
      ));
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      // The notice must already be visible during the reverse route animation.
      await tester.pump();
      expect(find.byTooltip('Cerrar aviso').hitTestable(), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(message).hitTestable(), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(successKey)).dy, lessThan(50));
      expect(tester.widget<Material>(find.byKey(successKey)).color,
          const Color(0xFF276749));
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      await tester.tap(find.byTooltip('Cerrar aviso'));
      await tester.pump();
      expect(find.byKey(successKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('confirmed save expires after five seconds', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return TextButton(
        onPressed: () => showSuccessNotice(context, 'Reporte enviado.'),
        child: const Text('Mostrar'),
      );
    })));
    await tester.tap(find.text('Mostrar'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(successKey), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(successKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('attachment error replaces success without stacking notices',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return Column(children: [
        TextButton(
          onPressed: () => showSuccessNotice(context, 'Reporte enviado.'),
          child: const Text('Confirmar'),
        ),
        TextButton(
          onPressed: () => showUploadError(context,
              'El reporte se envió, pero no se pudo adjuntar la imagen.'),
          child: const Text('Error'),
        ),
      ]);
    })));
    await tester.tap(find.text('Confirmar'));
    await tester.pump();
    // Use the callback: the top notice intentionally covers these controls.
    tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Error'))
        .onPressed!();
    await tester.pump();
    expect(find.byKey(successKey), findsNothing);
    expect(find.byKey(const ValueKey('upload-error-notice')), findsOneWidget);
    expect(find.byTooltip('Cerrar aviso').hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('accessible save confirmation stays until dismissed',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(accessibleNavigation: true),
        child: child!,
      ),
      home: Builder(
          builder: (context) => TextButton(
                onPressed: () =>
                    showSuccessNotice(context, 'Actividad creada.'),
                child: const Text('Mostrar'),
              )),
    ));
    await tester.tap(find.text('Mostrar'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(find.byTooltip('Cerrar aviso').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('Cerrar aviso'));
    await tester.pump();
    expect(find.byKey(successKey), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
