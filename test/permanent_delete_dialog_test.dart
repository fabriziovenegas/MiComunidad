import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/widgets/permanent_delete_dialog.dart';
import 'package:micomunidad/widgets/upload_error_notice.dart';

void main() {
  tearDown(dismissUploadError);
  for (final entity in ['proyecto', 'reporte']) {
    Future<void> open(WidgetTester tester, Future<void> Function() action,
        {required Future<bool> Function() offline}) async {
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showDialog<bool>(
                          context: context,
                          builder: (_) => PermanentDeleteDialog(
                              entity: entity,
                              name: 'Fictitious',
                              actionKey: 'delete-$entity:test',
                              onDelete: action,
                              isOffline: offline,
                              details: (_) =>
                                  'La eliminación quedó incompleta. Conserva el registro principal.')),
                      child: const Text('Open'))))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets(
        '$entity requires explicit confirmation and internet; permits retry',
        (tester) async {
      var offline = true;
      var calls = 0;
      await open(tester, () async {
        calls++;
      }, offline: () => Future.value(offline));
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      await tester.enterText(find.byType(TextField), 'CONFIRMAR');
      await tester.pump();
      await tester.tap(find.text('Eliminar definitivamente'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.text('Necesitas conexión para realizar esta acción'),
          findsOneWidget);
      expect(find.text('CONFIRMAR'), findsWidgets);
      offline = false;
      await tester.tap(find.text('Eliminar definitivamente'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.byType(PermanentDeleteDialog), findsNothing);
    });
    testWidgets('$entity slow shows specific message and blocks duplicates',
        (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      await open(tester, () {
        calls++;
        return pending.future;
      }, offline: () async => false);
      await tester.enterText(find.byType(TextField), 'CONFIRMAR');
      await tester.pump();
      await tester.tap(find.text('Eliminar definitivamente'));
      await tester.pump();
      await tester.tap(find.text('Eliminando...'));
      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(const ValueKey('save-warning-notice')), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(
          find.text(
              'La eliminación del $entity está tardando. Verifica tu conexión.'),
          findsOneWidget);
      expect(calls, 1);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      pending.complete();
      await tester.pumpAndSettle();
      expect(
          find.text(
              '${entity == 'proyecto' ? 'Proyecto' : 'Reporte'} eliminado definitivamente.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('$entity retains partial failure details and confirmation',
        (tester) async {
      var calls = 0;
      await open(tester, () async {
        if (++calls == 1) throw StateError('partial');
      }, offline: () async => false);
      await tester.enterText(find.byType(TextField), 'CONFIRMAR');
      await tester.pump();
      await tester.tap(find.text('Eliminar definitivamente'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'La eliminación quedó incompleta. Conserva el registro principal.'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('upload-error-notice')), findsOneWidget);
      expect(find.byKey(const ValueKey('save-success-notice')), findsNothing);
      await tester.tap(find.text('Eliminar definitivamente'));
      await tester.pumpAndSettle();
      expect(calls, 2);
    });
  }
}
