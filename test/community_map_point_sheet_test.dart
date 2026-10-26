import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/widgets/community_map_point_sheet.dart';
import 'package:micomunidad/widgets/upload_error_notice.dart';

Future<void> open(WidgetTester tester,
    {Future<void> Function()? onDelete}) async {
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      builder: (_) => CommunityMapPointSheet(
                          title: 'Referencia ficticia',
                          description: 'Descripción de prueba',
                          onDelete: onDelete)),
                  child: const Text('Abrir'))))));
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(dismissUploadError);
  testWidgets('read-only original references have no deletion control',
      (tester) async {
    await open(tester);
    expect(find.text('Referencia ficticia'), findsOneWidget);
    expect(find.text('Descripción de prueba'), findsOneWidget);
    expect(find.text('Eliminar punto'), findsNothing);
  });
  testWidgets('cancelling confirmation leaves the point unchanged',
      (tester) async {
    var calls = 0;
    await open(tester, onDelete: () async => calls++);
    await tester.tap(find.text('Eliminar punto'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no se puede deshacer'), findsOneWidget);
    expect(calls, 0);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Referencia ficticia'), findsOneWidget);
    expect(find.text('Eliminar punto'), findsOneWidget);
  });
  testWidgets(
      'confirming deletes exactly once and shows success after completion',
      (tester) async {
    var calls = 0;
    final gate = Completer<void>();
    await open(tester, onDelete: () {
      calls++;
      return gate.future;
    });
    await tester.tap(find.text('Eliminar punto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Punto eliminado.'), findsNothing);
    expect(find.text('Eliminando…'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CommunityMapPointSheet), findsNothing);
    expect(find.text('Punto eliminado.'), findsOneWidget);
  });
  testWidgets(
      'failure keeps the point open and permits retry without false success',
      (tester) async {
    var calls = 0;
    await open(tester, onDelete: () async {
      if (++calls == 1) throw StateError('Unavailable');
    });
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Eliminar punto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();
      if (i == 0) {
        expect(find.text('Referencia ficticia'), findsOneWidget);
        expect(find.text('Punto eliminado.'), findsNothing);
        expect(find.textContaining('No se pudo eliminar'), findsOneWidget);
      }
    }
    expect(calls, 2);
    expect(find.text('Punto eliminado.'), findsOneWidget);
  });
}
