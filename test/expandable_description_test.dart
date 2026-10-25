import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/widgets/expandable_description.dart';

Future<void> showDescription(WidgetTester tester, String text,
    {double width = 600,
    double scale = 1,
    bool bold = false,
    TextStyle? style,
    TextDirection direction = TextDirection.ltr}) async {
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale), boldText: bold),
      child: Directionality(textDirection: direction, child: child!),
    ),
    home: Scaffold(
        body: SingleChildScrollView(
            child: Align(
                alignment: AlignmentDirectional.topStart,
                child: SizedBox(
                    width: width,
                    child: ExpandableDescription(text: text, style: style))))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  for (final text in [
    '',
    'Descripción breve.',
    'Primera\nSegunda\nTercera\nCuarta'
  ]) {
    testWidgets('four or fewer actual lines show fully without a button: $text',
        (tester) async {
      await showDescription(tester, text);
      expect(find.text(text), findsOneWidget);
      expect(tester.widget<Text>(find.text(text)).maxLines, isNull);
      expect(find.text('Leer más'), findsNothing);
      expect(find.text('Leer menos'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'a fifth line can expand and collapse repeatedly without losing any text',
      (tester) async {
    const text = 'Primera\nSegunda\nTercera\nCuarta\nQuinta\nSexta';
    await showDescription(tester, text);
    final collapsedHeight = tester.getSize(find.text(text)).height;
    for (var attempt = 0; attempt < 2; attempt++) {
      expect(tester.widget<Text>(find.text(text)).maxLines, 4);
      expect(
          tester.widget<Text>(find.text(text)).overflow, TextOverflow.ellipsis);
      await tester.tap(find.text('Leer más'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text(text)).maxLines, isNull);
      expect(
          tester.getSize(find.text(text)).height, greaterThan(collapsedHeight));
      expect(find.text('Leer menos'), findsOneWidget);
      await tester.tap(find.text('Leer menos'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.text(text)).height, collapsedHeight);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'measures wrapping at the actual available width, not character count',
      (tester) async {
    const text =
        'Este texto se ajusta al ancho disponible y puede ocupar varias líneas en una pantalla pequeña.';
    await showDescription(tester, text, width: 150);
    expect(find.text('Leer más'), findsOneWidget);
    await showDescription(tester, text, width: 600);
    expect(find.text('Leer más'), findsNothing);
    expect(tester.widget<Text>(find.text(text)).maxLines, isNull);
  });

  testWidgets(
      'text scale is included when deciding whether four lines overflow',
      (tester) async {
    const text =
        'Una descripción de ejemplo que necesita más espacio cuando el tamaño de letra es mayor.';
    await showDescription(tester, text, width: 400);
    expect(find.text('Leer más'), findsNothing);
    await showDescription(tester, text, width: 400, scale: 2);
    expect(find.text('Leer más'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'new description resets expansion without leaking the previous text',
      (tester) async {
    const first = 'Uno\nDos\nTres\nCuatro\nCinco';
    const second = 'Otro uno\nOtro dos\nOtro tres\nOtro cuatro\nOtro cinco';
    await showDescription(tester, first);
    await tester.tap(find.text('Leer más'));
    await tester.pumpAndSettle();
    final originalElement = tester.element(find.byType(ExpandableDescription));
    await showDescription(tester, second);
    expect(tester.element(find.byType(ExpandableDescription)),
        same(originalElement));
    expect(find.text(first), findsNothing);
    expect(tester.widget<Text>(find.text(second)).maxLines, 4);
    expect(find.text('Leer más'), findsOneWidget);
    expect(find.text('Leer menos'), findsNothing);
  });

  testWidgets('empty and short replacements remove the button after expansion',
      (tester) async {
    await showDescription(tester, 'Uno\nDos\nTres\nCuatro\nCinco');
    await tester.tap(find.text('Leer más'));
    await tester.pumpAndSettle();
    await showDescription(tester, 'Breve');
    expect(find.byType(TextButton), findsNothing);
    await showDescription(tester, '');
    expect(find.byType(TextButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'custom description styling and accessibility bold text are retained',
      (tester) async {
    const text = 'Uno\nDos\nTres\nCuatro\nCinco';
    await showDescription(tester, text,
        bold: true,
        style:
            const TextStyle(fontSize: 18, height: 1.45, color: Colors.green));
    final style = tester.widget<Text>(find.text(text)).style!;
    expect(style.fontSize, 18);
    expect(style.height, 1.45);
    expect(style.color, Colors.green);
    expect(style.fontWeight, FontWeight.bold);
    expect(find.text('Leer más'), findsOneWidget);
  });

  testWidgets('independent descriptions do not expand together',
      (tester) async {
    const first = 'Uno\nDos\nTres\nCuatro\nCinco';
    const second = 'Primero\nSegundo\nTercero\nCuarto\nQuinto';
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: Column(children: [
      ExpandableDescription(text: first),
      ExpandableDescription(text: second)
    ])))));
    expect(find.text('Leer más'), findsNWidgets(2));
    await tester.tap(find.text('Leer más').first);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text(first)).maxLines, isNull);
    expect(tester.widget<Text>(find.text(second)).maxLines, 4);
    expect(find.text('Leer menos'), findsOneWidget);
    expect(find.text('Leer más'), findsOneWidget);
  });

  testWidgets(
      'RTL and narrow large-text layouts keep a usable read more button',
      (tester) async {
    final text = 'Texto de ejemplo para lectura completa. ' * 12;
    await showDescription(tester, text,
        width: 240, scale: 1.6, direction: TextDirection.rtl);
    expect(find.text('Leer más'), findsOneWidget);
    await tester.tap(find.text('Leer más'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text(text)).maxLines, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the control exposes its expanded state to accessibility',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await showDescription(tester, 'Uno\nDos\nTres\nCuatro\nCinco');
      final labels = find.byWidgetPredicate((widget) =>
          widget is Semantics && widget.properties.expanded != null);
      expect(tester.widget<Semantics>(labels).properties.expanded, isFalse);
      await tester.tap(find.text('Leer más'));
      await tester.pumpAndSettle();
      expect(tester.widget<Semantics>(labels).properties.expanded, isTrue);
    } finally {
      semantics.dispose();
    }
  });
}
