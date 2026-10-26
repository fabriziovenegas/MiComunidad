import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:micomunidad/widgets/agenda_presentation.dart';

final example = <String, dynamic>{
  'title': 'Asamblea vecinal',
  'location': 'Local comunal',
  'eventDate': Timestamp.fromDate(DateTime(2026, 11, 7, 17)),
  'description':
      'Revisaremos los avances y acordaremos las próximas actividades.',
};

Future<void> present(WidgetTester tester, Widget child,
    {double width = 412, double scale = 1}) async {
  tester.view.physicalSize = Size(width, 1600);
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
  setUpAll(() => initializeDateFormatting('es'));

  testWidgets(
      'preview shows date, title, time and location without duplicating description',
      (tester) async {
    var opened = 0;
    var deleted = 0;
    await present(
        tester,
        AgendaPreviewCard(
            data: example, onOpen: () => opened++, onDelete: () => deleted++));
    for (final text in [
      '7',
      'nov',
      'Asamblea vecinal',
      '17:00',
      'Local comunal'
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.text(example['description'] as String), findsNothing);
    expect(find.byIcon(Icons.access_time), findsOneWidget);
    expect(find.byIcon(Icons.location_on_outlined), findsOneWidget);
    await tester.tap(find.text('Asamblea vecinal'));
    expect(opened, 1);
    await tester.tap(find.byTooltip('Opciones'));
    await tester.pumpAndSettle();
    expect(deleted, 0);
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(deleted, 1);
    expect(opened, 1);
  });

  testWidgets('empty location adds neither a pin nor a dangling separator',
      (tester) async {
    await present(tester,
        AgendaPreviewCard(data: {...example, 'location': '  '}, onOpen: () {}));
    expect(find.byIcon(Icons.location_on_outlined), findsNothing);
    expect(find.text('17:00'), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);
    expect(find.textContaining('•'), findsNothing);
  });

  testWidgets('neighbor card provides opening without an administration menu',
      (tester) async {
    await present(tester, AgendaPreviewCard(data: example, onOpen: () {}));
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets(
      'administration menu edits without opening or deleting the activity',
      (tester) async {
    var edited = 0;
    var deleted = 0;
    var opened = 0;
    await present(
        tester,
        AgendaPreviewCard(
            data: example,
            onOpen: () => opened++,
            onEdit: () => edited++,
            onDelete: () => deleted++));
    await tester.tap(find.byTooltip('Opciones'));
    await tester.pumpAndSettle();
    expect(find.text('Editar actividad'), findsOneWidget);
    expect(find.text('Eliminar'), findsOneWidget);
    await tester.tap(find.text('Editar actividad'));
    await tester.pumpAndSettle();
    expect(edited, 1);
    expect(deleted, 0);
    expect(opened, 0);
  });

  testWidgets(
      'detail orders date and location before the full description, without another title',
      (tester) async {
    await present(tester, AgendaInformation(data: example));
    final date = find.text('07/11/2026 • 17:00');
    final location = find.text('Local comunal');
    final description = find.text(example['description'] as String);
    expect(date, findsOneWidget);
    expect(location, findsOneWidget);
    expect(description, findsOneWidget);
    expect(
        tester.getTopLeft(date).dy, lessThan(tester.getTopLeft(location).dy));
    expect(tester.getTopLeft(location).dy,
        lessThan(tester.getTopLeft(description).dy));
    expect(find.text('Asamblea vecinal'), findsNothing);
    expect(find.text('Leer más'), findsNothing);
    expect(find.text('Descripción'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets(
      'detail whitelists content and never displays internal identity or credentials',
      (tester) async {
    await present(
        tester,
        AgendaInformation(data: {
          ...example,
          'email': 'private@example.com',
          'dni': '00000001',
          'uid': 'private-uid',
          'internalNotes': 'Private notes',
          'url': 'https://example.com/secret'
        }));
    for (final value in [
      'private@example.com',
      '00000001',
      'private-uid',
      'Private notes',
      'https://example.com/secret'
    ]) {
      expect(find.textContaining(value), findsNothing);
    }
  });

  testWidgets(
      'missing event fields add no invented location, date or description',
      (tester) async {
    await present(
        tester,
        const AgendaInformation(data: {
          'eventDate': 'invalid-date',
          'location': '  ',
          'description': '\n'
        }));
    expect(find.byType(Text), findsNothing);
    expect(find.byType(Icon), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'documents show their actual filename, with independent open and delete actions',
      (tester) async {
    var opened = 0;
    var deleted = 0;
    await present(
        tester,
        AgendaDocumentTile(
            name: 'Acta de asamblea.pdf',
            isPdf: true,
            onOpen: () => opened++,
            onDelete: () => deleted++));
    expect(find.text('Acta de asamblea.pdf'), findsOneWidget);
    expect(find.text('Acta PDF'), findsNothing);
    expect(find.byIcon(Icons.picture_as_pdf), findsOneWidget);
    await tester.tap(find.text('Acta de asamblea.pdf'));
    expect(opened, 1);
    await tester.tap(find.byTooltip('Eliminar archivo'));
    expect(deleted, 1);
    expect(opened, 1);
  });

  testWidgets('an image attached as minutes keeps its filename and image icon',
      (tester) async {
    await present(
        tester,
        AgendaDocumentTile(
            name: 'Acuerdos fotografiados.png', isPdf: false, onOpen: () {}));
    expect(find.text('Acuerdos fotografiados.png'), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.byTooltip('Eliminar archivo'), findsNothing);
  });

  for (final pdf in [true, false]) {
    testWidgets(
        'legacy ${pdf ? 'PDF' : 'image'} without a filename keeps a readable fallback',
        (tester) async {
      await present(
          tester, AgendaDocumentTile(name: ' ', isPdf: pdf, onOpen: () {}));
      expect(
          find.text(pdf ? 'Documento PDF' : 'Imagen adjunta'), findsOneWidget);
    });
  }

  testWidgets('long descriptions retain Leer más and Leer menos',
      (tester) async {
    final description =
        List.generate(12, (i) => 'Texto de prueba $i.').join('\n');
    await present(tester,
        AgendaInformation(data: {...example, 'description': description}));
    expect(tester.widget<Text>(find.text(description)).maxLines, 4);
    await tester.tap(find.text('Leer más'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text(description)).maxLines, isNull);
    expect(find.text('Leer menos'), findsOneWidget);
  });

  for (final width in [320.0, 412.0, 600.0]) {
    for (final scale in [1.0, 1.6, 2.0]) {
      testWidgets(
          'agenda fields and filenames fit width $width and text scale $scale',
          (tester) async {
        final long = {
          ...example,
          'title':
              'Reunión de coordinación para organizar las siguientes actividades vecinales',
          'location':
              'Ubicación de demostración suficientemente larga para comprobar la distribución',
          'description': 'Descripción completa de la actividad. ' * 12
        };
        await present(
            tester,
            Column(children: [
              AgendaPreviewCard(data: long, onOpen: () {}, onDelete: () {}),
              AgendaInformation(data: long),
              AgendaDocumentTile(
                  name:
                      'Acta de asamblea con acuerdos y observaciones de la reunión.pdf',
                  isPdf: true,
                  onOpen: () {},
                  onDelete: () {}),
            ]),
            width: width,
            scale: scale);
        expect(tester.takeException(), isNull);
        expect(find.text('17:00'), findsOneWidget);
        expect(find.byTooltip('Eliminar archivo'), findsOneWidget);
      });
    }
  }
}
