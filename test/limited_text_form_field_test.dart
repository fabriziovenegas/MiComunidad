import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/widgets/limited_text_form_field.dart';

void main() {
  for (final limit in [160, 300, 320, 1000, 4000]) {
    testWidgets(
        'limit $limit preserves pasted text and prevents form submission',
        (tester) async {
      final form = GlobalKey<FormState>();
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: Form(
        key: form,
        child: LimitedTextFormField(
            characterLimit: limit,
            controller: controller,
            validator: (value) => value!.isEmpty ? 'Obligatorio' : null),
      )))));
      expect(form.currentState!.validate(), false);
      await tester.enterText(find.byType(TextFormField), 'a' * limit);
      await tester.pump();
      expect(find.text('$limit/$limit'), findsOneWidget);
      expect(form.currentState!.validate(), true);
      final pasted = 'a' * (limit + 1);
      await tester.enterText(find.byType(TextFormField), pasted);
      await tester.pump();
      expect(controller.text, pasted);
      expect(find.text('${limit + 1}/$limit'), findsOneWidget);
      expect(form.currentState!.validate(), false);
      expect(
          find.text('No puede superar los $limit caracteres.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Corregido');
      await tester.pump();
      expect(form.currentState!.validate(), true);
      expect(
          find.text('No puede superar los $limit caracteres.'), findsNothing);
    });
  }
  testWidgets(
      'Unicode, external changes and rebuilding preserve count and text',
      (tester) async {
    final controller = TextEditingController(text: 'á😀');
    addTearDown(controller.dispose);
    Widget screen() => MaterialApp(
        home: Scaffold(
            body: LimitedTextFormField(
                controller: controller, characterLimit: 160)));
    await tester.pumpWidget(screen());
    expect(find.text('3/160'), findsNothing);
    await tester.tap(find.byType(TextFormField));
    await tester.pump();
    expect(find.text('3/160'), findsOneWidget);
    controller.text = 'Texto restaurado';
    await tester.pump();
    expect(find.text('${controller.text.length}/160'), findsOneWidget);
    await tester.pumpWidget(screen());
    expect(controller.text, 'Texto restaurado');
    controller.clear();
    await tester.pump();
    expect(find.text('0/160'), findsOneWidget);
  });
  testWidgets(
      'counter follows focus but over-limit warning remains visible after blur',
      (tester) async {
    final controller = TextEditingController(text: 'Hola');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      LimitedTextFormField(controller: controller, characterLimit: 160),
      const TextField(decoration: InputDecoration(labelText: 'Otro campo')),
    ]))));
    expect(find.text('4/160'), findsNothing);
    await tester.tap(find.byType(TextFormField));
    await tester.pump();
    expect(find.text('4/160'), findsOneWidget);
    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    expect(find.text('4/160'), findsNothing);
    controller.text = 'a' * 161;
    await tester.pump();
    expect(find.text('161/160'), findsOneWidget);
    expect(find.text('No puede superar los 160 caracteres.'), findsOneWidget);
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('counter and error wrap at 320px with scale $scale',
        (tester) async {
      tester.view.physicalSize = const Size(320, 1200);
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
                  padding: const EdgeInsets.all(24),
                  child: LimitedTextFormField(
                    characterLimit: 160,
                    initialValue: 'a' * 161,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Título'),
                  )))));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('161/160'), findsOneWidget);
      expect(find.text('No puede superar los 160 caracteres.'), findsOneWidget);
    });
  }
}
