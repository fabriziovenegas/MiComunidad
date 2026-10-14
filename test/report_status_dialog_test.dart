import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/widgets/report_status_dialog.dart';
import 'package:micomunidad/models/report_edit.dart';
import 'package:micomunidad/models/user_model.dart';

Future<void> openStatus(
    WidgetTester tester, String initial, Future<void> Function(String) save,
    {ValueChanged<String?>? onClosed}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            final result = await showDialog<String>(
              context: context,
              barrierDismissible: false,
              builder: (_) =>
                  ReportStatusDialog(initialStatus: initial, onSave: save),
            );
            onClosed?.call(result);
          },
          child: const Text('Open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'other-author admin opens only a state selector without content fields',
      (tester) async {
    final admin = AppUser(
        userId: 'admin-demo',
        email: 'admin@example.com',
        nombre: 'Demo Admin',
        role: UserRole.admin,
        approvalStatus: 'aprobado',
        joinDate: DateTime.utc(2026),
        communityId: 'demo',
        createdAt: DateTime.utc(2026));
    final other = {
      'createdBy': 'neighbor-demo',
      'moderationStatus': 'aprobado',
      'status': 'en_proceso'
    };
    expect(reportUsesStatusOnlyDialog(admin, other, admin.userId), isTrue);
    await openStatus(tester, other['status']!, (_) async {});
    expect(find.text('Título'), findsNothing);
    expect(find.text('Descripción'), findsNothing);
    expect(find.text('Ubicación'), findsNothing);
    expect(find.text('Categoría'), findsNothing);
    expect(find.text('Prioridad'), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.text('Estado'), findsOneWidget);
    expect(find.textContaining('no permite editar'), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
  });

  for (final entry in {
    'pendiente': 'Por Atender',
    'en_proceso': 'En Proceso',
    'resuelto': 'Resuelto',
  }.entries) {
    testWidgets('load and confirm ${entry.key} independently from content',
        (tester) async {
      String? written;
      String? closed;
      await openStatus(tester, entry.key, (status) async => written = status,
          onClosed: (status) => closed = status);
      expect(find.text(entry.value), findsOneWidget);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(written, entry.key);
      expect(closed, entry.key);
      expect(find.byType(ReportStatusDialog), findsNothing);
    });
  }

  testWidgets(
      'wait for the write, block duplicate saves and preserve selection',
      (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    String? closed;
    await openStatus(tester, 'resuelto', (_) {
      calls++;
      return pending.future;
    }, onClosed: (status) => closed = status);
    await tester.tap(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    expect(calls, 1);
    expect(closed, isNull);
    expect(find.text('Guardando…'), findsOneWidget);
    expect(tester.widget<TextButton>(find.byType(TextButton).last).onPressed,
        isNull);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(ReportStatusDialog), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    expect(closed, 'resuelto');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'denied state write is not reported as success and can be retried',
      (tester) async {
    var calls = 0;
    String? closed;
    await openStatus(tester, 'resuelto', (status) async {
      expect(status, 'resuelto');
      if (++calls == 1) {
        throw FirebaseException(
            plugin: 'cloud_firestore', code: 'permission-denied');
      }
    }, onClosed: (status) => closed = status);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(closed, isNull);
    expect(find.textContaining('Firebase rechazó'), findsOneWidget);
    expect(find.text('Resuelto'), findsOneWidget);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(closed, 'resuelto');
  });
}
