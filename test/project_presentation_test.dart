import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/widgets/project_presentation.dart';
import 'package:micomunidad/widgets/content_comment_composer.dart';

const example = <String, dynamic>{
  'title': 'Proyecto de prueba',
  'status': 'en_proceso',
  'location': 'Local Comunal',
  'progress': 48,
  'description': 'Esta descripción se reserva para el panel abierto.',
};

Future<void> present(WidgetTester tester, Widget child,
    {double width = 412, double scale = 1}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: Scaffold(
        body: SingleChildScrollView(
            padding: const EdgeInsets.all(16), child: child)),
  ));
}

void main() {
  testWidgets(
      'preview keeps identity, state, location, percentage and actions without description or bar',
      (tester) async {
    var opened = 0;
    var edited = 0;
    await present(
        tester,
        ProjectPreviewCard(
            data: example, onOpen: () => opened++, onEdit: () => edited++));
    for (final text in [
      'Proyecto de prueba',
      'En proceso',
      'Local Comunal',
      '48 %',
      'Fotos y comentarios'
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.text(example['description'] as String), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.location_on_outlined), findsOneWidget);
    await tester.tap(find.text('Fotos y comentarios'));
    expect(opened, 1);
    await tester.tap(find.byTooltip('Editar proyecto'));
    expect(edited, 1);
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('neighbor preview has no edit action', (tester) async {
    await present(tester, ProjectPreviewCard(data: example, onOpen: () {}));
    expect(find.byTooltip('Editar proyecto'), findsNothing);
    expect(find.text('Fotos y comentarios'), findsOneWidget);
  });

  testWidgets('expanded information keeps bar before location and description',
      (tester) async {
    await present(tester, const ProjectInformation(data: example));
    final bar = find.byType(LinearProgressIndicator);
    expect(tester.widget<LinearProgressIndicator>(bar).value, .48);
    expect(find.text('48 % de avance'), findsOneWidget);
    expect(tester.getTopLeft(bar).dy,
        lessThan(tester.getTopLeft(find.text('Local Comunal')).dy));
    expect(
        tester.getTopLeft(find.text('Local Comunal')).dy,
        lessThan(
            tester.getTopLeft(find.text(example['description'] as String)).dy));
    expect(find.text('Proyecto de prueba'), findsNothing);
  });

  for (final width in [320.0, 412.0, 600.0]) {
    for (final scale in [1.0, 1.6, 2.0]) {
      testWidgets('long project fields fit width $width and text scale $scale',
          (tester) async {
        final data = {
          ...example,
          'title':
              'Mejoramiento del local para actividades comunitarias y reuniones vecinales',
          'location':
              'Ubicación ficticia con varias referencias para comprobar el ajuste del texto',
          'description':
              'Descripción ampliada para comprobar la lectura. ' * 20,
        };
        await present(
            tester,
            Column(children: [
              ProjectPreviewCard(data: data, onOpen: () {}, onEdit: () {}),
              ProjectInformation(data: data),
            ]),
            width: width,
            scale: scale);
        expect(tester.takeException(), isNull);
        expect(find.text('48 %'), findsOneWidget);
        expect(find.text('48 % de avance'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
      });
    }
  }

  testWidgets(
      'archived preview keeps information access and restoration controls',
      (tester) async {
    await present(
        tester,
        ProjectPreviewCard(
          data: example,
          onOpen: () {},
          detailsLabel: 'Ver información',
          detailsIcon: Icons.visibility_outlined,
          actions: Wrap(children: [
            TextButton(onPressed: () {}, child: const Text('Restaurar'))
          ]),
        ));
    expect(find.text('Ver información'), findsOneWidget);
    expect(find.text('Restaurar'), findsOneWidget);
    expect(find.byTooltip('Editar proyecto'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('empty photos are explained without adding example images',
      (tester) async {
    await present(tester, const ProjectPhotosEmptyState());
    expect(find.text('Aún no hay fotografías.'), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets(
      'project composer preserves send logic and supports a narrow layout',
      (tester) async {
    String? sent;
    await present(
        tester,
        ContentCommentComposer(
            projectStyle: true,
            onSend: (text) async {
              sent = text;
            }),
        width: 320,
        scale: 1.6);
    await tester.enterText(find.byType(TextField), 'Comentario de prueba');
    await tester.tap(find.byTooltip('Enviar comentario'));
    await tester.pumpAndSettle();
    expect(sent, 'Comentario de prueba');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(tester.takeException(), isNull);
  });
}
