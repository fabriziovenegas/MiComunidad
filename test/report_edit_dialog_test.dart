import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/widgets/report_edit_dialog.dart';
import 'package:micomunidad/widgets/report_status_dialog.dart';
import 'package:micomunidad/services/report_content_editor.dart';

const data = {
  'title': 'Demo title',
  'description': 'Demo description',
  'location': 'Demo location',
  'category': 'obras',
  'priority': 'alta',
  'status': 'en_proceso',
  'moderationStatus': 'aprobado',
};

Future<void> openDialog(WidgetTester tester, SaveReportEdit? onSave,
    {ValueChanged<bool?>? onClosed,
    Future<String?> Function()? onChangeStatus,
    Map<String, dynamic> reportData = data,
    bool allowResolvedContentEditing = false,
    GlobalKey<NavigatorState>? navigatorKey}) async {
  await tester.pumpWidget(MaterialApp(
    navigatorKey: navigatorKey,
    home: Builder(
        builder: (context) => Scaffold(
                body: TextButton(
              onPressed: () async {
                final saved = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => ReportEditDialog(
                          data: reportData,
                          onSave: onSave,
                          onChangeStatus: onChangeStatus,
                          allowResolvedContentEditing:
                              allowResolvedContentEditing,
                        ));
                onClosed?.call(saved);
              },
              child: const Text('Open'),
            ))),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('admin owner can resolve and save own content without reopening',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final ref = db.collection('reports').doc('own-demo');
    await ref.set({...data, 'createdBy': 'admin-demo'});
    await db.collection('users').doc('admin-demo').set({
      'role': 'admin',
      'approvalStatus': 'aprobado',
    });
    final editor =
        ReportContentEditor(firestore: db, currentUserId: () => 'admin-demo');
    await openDialog(tester, (draft) => editor.save(ref.id, draft),
        allowResolvedContentEditing: true, onChangeStatus: () async {
      await ref.update(
          {'status': 'resuelto', 'updatedAt': FieldValue.serverTimestamp()});
      return 'resuelto';
    });
    await tester.enterText(
        find.byType(TextFormField).first, 'Edited own resolved title');
    await tester.ensureVisible(find.text('Actualizar estado'));
    await tester.tap(find.text('Actualizar estado'));
    await tester.pumpAndSettle();
    expect((await ref.get()).data()!['status'], 'resuelto');
    expect(find.text('Estado actualizado: Resuelto.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField).first).readOnly,
        isFalse);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.byType(ReportEditDialog), findsNothing);
    final after = (await ref.get()).data()!;
    expect(after['title'], 'Edited own resolved title');
    expect(after['status'], 'resuelto');
    expect(after['createdBy'], 'admin-demo');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'admin owner opens existing resolved report with editable content',
      (tester) async {
    await openDialog(tester, (_) async {},
        reportData: {...data, 'status': 'resuelto'},
        allowResolvedContentEditing: true,
        onChangeStatus: () async => 'resuelto');
    expect(find.text('Editar mi reporte'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField).first).readOnly,
        isFalse);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    expect(find.textContaining('solo lectura'), findsNothing);
  });

  testWidgets(
      'resolve, reopen and save without a stale content permission error',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final reference = db.collection('reports').doc('demo-report');
    await reference.set({...data, 'createdBy': 'admin-demo'});
    final key = GlobalKey<NavigatorState>();
    final editor =
        ReportContentEditor(firestore: db, currentUserId: () => 'admin-demo');
    await openDialog(tester, (draft) => editor.save(reference.id, draft),
        navigatorKey: key, onChangeStatus: () async {
      final current = (await reference.get()).data()!;
      return showDialog<String>(
        context: key.currentState!.context,
        barrierDismissible: false,
        builder: (_) => ReportStatusDialog(
          initialStatus: current['status'] as String,
          onSave: (status) => reference.update({
            'status': status,
            'updatedAt': FieldValue.serverTimestamp(),
          }),
        ),
      );
    });
    await tester.enterText(
        find.byType(TextFormField).first, 'Kept draft title');

    Future<void> changeTo(String label) async {
      await tester.ensureVisible(find.text('Actualizar estado'));
      await tester.tap(find.text('Actualizar estado'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(ReportStatusDialog),
          matching: find.byType(DropdownButtonFormField<String>)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(ReportStatusDialog),
          matching: find.widgetWithText(FilledButton, 'Guardar')));
      await tester.pumpAndSettle();
    }

    await changeTo('Resuelto');
    expect((await reference.get()).data()!['status'], 'resuelto');
    expect((await reference.get()).data()!['title'], 'Demo title');
    expect(find.text('Estado actualizado: Resuelto.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(tester.widget<TextField>(find.byType(TextField).first).readOnly,
        isTrue);
    expect(find.textContaining('No tienes permiso'), findsNothing);
    expect(find.text('Kept draft title'), findsOneWidget);

    await changeTo('En Proceso');
    expect((await reference.get()).data()!['status'], 'en_proceso');
    expect(tester.widget<TextField>(find.byType(TextField).first).readOnly,
        isFalse);
    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect((await reference.get()).data()!['title'], 'Kept draft title');
    expect(find.byType(ReportEditDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resolved own report starts read-only but can be reopened',
      (tester) async {
    await openDialog(tester, (_) async {},
        reportData: {...data, 'status': 'resuelto'},
        onChangeStatus: () async => 'pendiente');
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.ensureVisible(find.text('Actualizar estado'));
    await tester.tap(find.text('Actualizar estado'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    expect(find.text('Estado actualizado: Por Atender.'), findsOneWidget);
  });

  testWidgets('canceling status does not change content eligibility',
      (tester) async {
    await openDialog(tester, (_) async {}, onChangeStatus: () async => null);
    await tester.ensureVisible(find.text('Actualizar estado'));
    await tester.tap(find.text('Actualizar estado'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Estado actualizado:'), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
  });

  testWidgets('reopening another author report never enables content editing',
      (tester) async {
    await openDialog(tester, null,
        reportData: {...data, 'status': 'resuelto'},
        onChangeStatus: () async => 'en_proceso');
    await tester.ensureVisible(find.text('Actualizar estado'));
    await tester.tap(find.text('Actualizar estado'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(tester.widget<TextField>(find.byType(TextField).first).readOnly,
        isTrue);
  });

  testWidgets('status action is absent without administrator callback',
      (tester) async {
    await openDialog(tester, (_) async {});
    expect(find.text('Actualizar estado'), findsNothing);
  });

  testWidgets('status action is below priority and separate from content save',
      (tester) async {
    var stateCalls = 0;
    ReportEditDraft? saved;
    await openDialog(tester, (draft) async => saved = draft,
        onChangeStatus: () async {
      stateCalls++;
      return 'en_proceso';
    });
    await tester.enterText(find.byType(TextFormField).first, 'Unsaved title');
    await tester.ensureVisible(find.text('Actualizar estado'));
    expect(tester.getTopLeft(find.text('Actualizar estado')).dy,
        greaterThan(tester.getTopLeft(find.text('Prioridad')).dy));
    await tester.tap(find.text('Actualizar estado'));
    await tester.pumpAndSettle();
    expect(stateCalls, 1);
    expect(saved, isNull);
    expect(find.byType(ReportEditDialog), findsOneWidget);
    expect(find.text('Unsaved title'), findsOneWidget);
    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(saved!.title, 'Unsaved title');
  });

  testWidgets('status action blocks duplicate actions and simultaneous saving',
      (tester) async {
    final pending = Completer<String?>();
    var stateCalls = 0;
    var saveCalls = 0;
    await openDialog(tester, (_) async => saveCalls++, onChangeStatus: () {
      stateCalls++;
      return pending.future;
    });
    await tester.ensureVisible(find.text('Actualizar estado'));
    await tester.tap(find.text('Actualizar estado'));
    await tester.tap(find.text('Actualizar estado'));
    await tester.pump();
    expect(stateCalls, 1);
    expect(saveCalls, 0);
    expect(find.text('Actualizando…'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    pending.complete('en_proceso');
    await tester.pumpAndSettle();
    expect(find.text('Actualizar estado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('status failure preserves content and allows retry',
      (tester) async {
    var calls = 0;
    await openDialog(tester, (_) async {}, onChangeStatus: () async {
      if (++calls == 1) {
        throw FirebaseException(
            plugin: 'cloud_firestore', code: 'permission-denied');
      }
      return 'en_proceso';
    });
    await tester.enterText(find.byType(TextFormField).first, 'Kept title');
    await tester.ensureVisible(find.text('Actualizar estado'));
    await tester.tap(find.text('Actualizar estado'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('No se pudo actualizar el estado'), findsOneWidget);
    expect(find.text('Kept title'), findsOneWidget);
    await tester.ensureVisible(find.text('Actualizar estado'));
    await tester.tap(find.text('Actualizar estado'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(
        find.textContaining('No se pudo actualizar el estado'), findsNothing);
  });

  testWidgets('status action is disabled while content is saving',
      (tester) async {
    final pending = Completer<void>();
    await openDialog(tester, (_) => pending.future,
        onChangeStatus: () async => 'en_proceso');
    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    pending.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'load original values and validate empty text before calling save',
      (tester) async {
    var calls = 0;
    await openDialog(tester, (_) async {
      calls++;
    });
    expect(find.text('Demo title'), findsOneWidget);
    expect(find.text('Demo description'), findsOneWidget);
    expect(find.text('Obras'), findsOneWidget);
    expect(find.text('Alta'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '   ');
    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    expect(calls, 0);
    expect(find.text('Este campo es obligatorio.'), findsOneWidget);
  });

  testWidgets('wait for confirmation, prevent duplicates and block dismissal',
      (tester) async {
    final pending = Completer<void>();
    final key = GlobalKey<NavigatorState>();
    var calls = 0;
    bool? saved;
    await openDialog(tester, (_) {
      calls++;
      return pending.future;
    }, navigatorKey: key, onClosed: (value) => saved = value);
    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    expect(calls, 1);
    expect(saved, isNull);
    expect(find.text('Guardando…'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancelar'))
            .onPressed,
        isNull);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    for (final field
        in tester.widgetList<TextFormField>(find.byType(TextFormField))) {
      expect(field.enabled, isFalse);
    }
    await key.currentState!.maybePop();
    await tester.pump();
    expect(find.byType(ReportEditDialog), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    expect(find.byType(ReportEditDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('permission error keeps entered values and permits retry',
      (tester) async {
    var calls = 0;
    ReportEditDraft? result;
    await openDialog(tester, (draft) async {
      calls++;
      if (calls == 1) {
        throw FirebaseException(
            plugin: 'cloud_firestore', code: 'permission-denied');
      }
      result = draft;
    });
    await tester.enterText(find.byType(TextFormField).first, 'Edited title');
    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Edited title'), findsOneWidget);
    expect(find.textContaining('Tus cambios se conservan'), findsOneWidget);
    expect(find.byType(ReportEditDialog), findsOneWidget);
    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(result!.title, 'Edited title');
    expect(find.byType(ReportEditDialog), findsNothing);
  });

  testWidgets('a dialog without a save callback cannot write', (tester) async {
    await openDialog(tester, null);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(find.text('Este reporte no permite editar su contenido.'),
        findsOneWidget);
  });
}
