import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/widgets/content_comment_tile.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('long unbroken comment is compact and expands at scale $scale',
        (tester) async {
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var deletes = 0;
      final text = 'n' * 1000;
      await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: Scaffold(
              body: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: ContentCommentTile(
                    author: 'Nombre completo de una persona de demostración',
                    text: text,
                    date: '30 de octubre de 2026',
                    onDelete: () => deletes++,
                  )))));
      expect(tester.takeException(), isNull);
      expect(find.text('Leer más'), findsOneWidget);
      final collapsed = tester.getSize(find.byType(ContentCommentTile)).height;
      expect(tester.widget<Text>(find.text(text)).maxLines, 4);
      expect(tester.getTopLeft(find.byType(CircleAvatar)).dy,
          lessThan(tester.getTopLeft(find.text(text)).dy));
      expect(tester.getTopLeft(find.byTooltip('Opciones del comentario')).dy,
          lessThan(tester.getTopLeft(find.text(text)).dy));
      await tester.tap(find.text('Leer más'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text(text)).maxLines, isNull);
      expect(tester.getSize(find.byType(ContentCommentTile)).height,
          greaterThan(collapsed));
      await tester.ensureVisible(find.text('Leer menos'));
      await tester.tap(find.text('Leer menos'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Opciones del comentario'));
      await tester.tap(find.byTooltip('Opciones del comentario'));
      await tester.pumpAndSettle();
      expect(deletes, 0);
      await tester.tap(find.text('Eliminar comentario'));
      await tester.pumpAndSettle();
      expect(deletes, 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'short comment needs no toggle and read-only shows no delete action',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: ContentCommentTile(
                author: 'Vecino', text: 'Gracias por el aviso.'))));
    expect(find.text('Gracias por el aviso.'), findsOneWidget);
    expect(find.text('Leer más'), findsNothing);
    expect(find.byTooltip('Opciones del comentario'), findsNothing);
  });
}
