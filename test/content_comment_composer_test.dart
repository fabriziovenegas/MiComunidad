import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/widgets/content_comment_composer.dart';

Future<void> render(WidgetTester tester, Future<void> Function(String) send,
        {bool enabled = true}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: ContentCommentComposer(onSend: send, enabled: enabled)),
    ));

void main() {
  testWidgets(
      'waits for save, blocks duplicate presses and clears only after success',
      (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    await render(tester, (text) {
      calls++;
      expect(text, 'Demo follow-up');
      return pending.future;
    });
    await tester.enterText(find.byType(TextField), ' Demo follow-up ');
    await tester.tap(find.byTooltip('Enviar comentario'));
    await tester.tap(find.byTooltip('Enviar comentario'));
    await tester.pump();
    expect(calls, 1);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        ' Demo follow-up ');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(find.text('Comentario publicado.'), findsOneWidget);
  });

  testWidgets(
      'failure keeps the text and permits retry without showing success',
      (tester) async {
    var calls = 0;
    await render(tester, (_) async {
      if (++calls == 1) throw StateError('Demo error');
    });
    await tester.enterText(find.byType(TextField), 'Kept comment');
    await tester.tap(find.byTooltip('Enviar comentario'));
    await tester.pumpAndSettle();
    expect(find.text('Kept comment'), findsOneWidget);
    expect(find.textContaining('Tu texto se conserva'), findsOneWidget);
    expect(find.text('Comentario publicado.'), findsNothing);
    await tester.tap(find.byTooltip('Enviar comentario'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('empty or oversized comments do not write', (tester) async {
    var calls = 0;
    await render(tester, (_) async => calls++);
    for (final text in [' ', 'x' * 1001]) {
      await tester.enterText(find.byType(TextField), text);
      await tester.tap(find.byTooltip('Enviar comentario'));
      await tester.pumpAndSettle();
    }
    expect(calls, 0);
  });

  testWidgets('disabled composer does not offer an enabled send action',
      (tester) async {
    await render(tester, (_) async {}, enabled: false);
    expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
  });

  testWidgets(
      'closing the sheet during a write does not clear a disposed controller',
      (tester) async {
    final pending = Completer<void>();
    await render(tester, (_) => pending.future);
    await tester.enterText(find.byType(TextField), 'Demo');
    await tester.tap(find.byTooltip('Enviar comentario'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
