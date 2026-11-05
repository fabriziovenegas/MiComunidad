import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:micomunidad/models/user_model.dart';
import 'package:micomunidad/screens/profile_screen.dart';
import 'package:micomunidad/screens/neighbor/agenda_screen.dart';
import 'package:micomunidad/services/event_content_editor.dart';
import 'package:micomunidad/services/pending_content_service.dart';
import 'package:micomunidad/services/content_delivery.dart';
import 'package:micomunidad/widgets/agenda_presentation.dart';
import 'package:micomunidad/widgets/upload_error_notice.dart';

final user = AppUser(
    userId: 'fictional-admin',
    email: 'admin@example.com',
    nombre: 'Fictional Admin',
    role: UserRole.admin,
    approvalStatus: 'aprobado',
    joinDate: DateTime(2026),
    phone: '000000001',
    dni: '00000001',
    address: 'Fictional address',
    timeLivingHere: '1 a 5 años',
    reason: 'Fictional test',
    communityId: 'demo',
    createdAt: DateTime(2026));

class ControlledEditor extends EventContentEditor {
  ControlledEditor(this.action)
      : super(
            firestore: FakeFirebaseFirestore(),
            currentUserId: () => user.userId);
  final Future<void> Function() action;
  int calls = 0;
  @override
  Future<void> save(String id, Map<String, dynamic> fields) async {
    calls++;
    expect(id, 'activity');
    expect(fields['title'], 'Fictional activity');
    await action();
  }
}

class NoCreation extends ContentDelivery {
  @override
  Future<void> deliver(PendingContent item) async =>
      throw StateError('Editing must not create queued records');
}

void main() {
  setUpAll(() => initializeDateFormatting('es'));
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(dismissUploadError);
  Future<void> profile(WidgetTester tester,
      {required Future<bool> Function() offline,
      required Future<void> Function() save}) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: ProfileScreen(
            user: user,
            isOffline: offline,
            onSave: (
                    {required nombre,
                    required dni,
                    required phone,
                    required email,
                    required address,
                    required timeLivingHere,
                    required reason}) =>
                save())));
    await tester.ensureVisible(find.text('Guardar cambios'));
  }

  testWidgets('profile offline preserves fields and allows a later retry',
      (tester) async {
    var offline = true;
    var calls = 0;
    await profile(tester,
        offline: () async => offline,
        save: () async {
          calls++;
        });
    await tester.enterText(
        find.byType(TextFormField).first, 'Updated Fictional Admin');
    await tester.ensureVisible(find.text('Guardar cambios'));
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Necesitas conexión para guardar los cambios'),
        findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'Updated Fictional Admin');
    offline = false;
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Cambios guardados'), findsOneWidget);
  });

  testWidgets(
      'profile warns after ten seconds without duplicate saves or false success',
      (tester) async {
    final ack = Completer<void>();
    var calls = 0;
    await profile(tester,
        offline: () async => false,
        save: () {
          calls++;
          return ack.future;
        });
    await tester.tap(find.text('Guardar cambios'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));
    expect(find.byKey(const ValueKey('save-warning-notice')), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('El guardado está tardando. Espera un momento'),
        findsOneWidget);
    expect(find.text('Cambios guardados'), findsNothing);
    expect(tester.widget<PopScope>(find.byType(PopScope).last).canPop, true);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(calls, 1);
    ack.complete();
    await tester.pumpAndSettle();
    expect(find.text('Cambios guardados'), findsOneWidget);
    expect(find.byKey(const ValueKey('save-warning-notice')), findsNothing);
  });

  testWidgets('profile hides native Java exception text and remains retryable',
      (tester) async {
    await profile(tester,
        offline: () async => false,
        save: () async {
          throw FirebaseFunctionsException(
              code: 'unavailable',
              message: 'java.net.UnknownHostException PRIVATE_DIAGNOSTIC');
        });
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    expect(find.textContaining('PRIVATE_DIAGNOSTIC'), findsNothing);
    expect(find.textContaining('java.net'), findsNothing);
    expect(
        find.text(
            'No se pudo conectar. Revisa tu conexión e inténtalo nuevamente.'),
        findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    expect(find.text('Cambios guardados'), findsNothing);
  });

  Future<void> activity(WidgetTester tester, ControlledEditor editor,
      Future<bool> Function() offline) async {
    final db = FakeFirebaseFirestore();
    await db.doc('events/activity').set({
      'title': 'Fictional activity',
      'description': 'Fictional notes',
      'location': 'Fictional location',
      'eventDate': Timestamp.fromDate(DateTime(2026, 11, 20))
    });
    final rows = await db.collection('events').get();
    final folder = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('activity-edit-wait-')))!;
    addTearDown(() async {
      final resolved = await folder.resolveSymbolicLinks();
      expect(resolved, contains('activity-edit-wait-'));
      await Directory(resolved).delete(recursive: true);
    });
    final queue = PendingContentService(
        directory: () async => folder,
        currentUserId: () => user.userId,
        delivery: NoCreation());
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AgendaScreen(
                user: user,
                eventStream: Stream.value(rows),
                pendingContent: queue,
                eventEditor: editor,
                isOffline: offline))));
    await tester.pumpAndSettle();
    tester.widget<AgendaPreviewCard>(find.byType(AgendaPreviewCard)).onEdit!();
    await tester.pumpAndSettle();
  }

  testWidgets('editing activity offline preserves dialog and retries online',
      (tester) async {
    var offline = true;
    final editor = ControlledEditor(() async {});
    await activity(tester, editor, () async => offline);
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    expect(editor.calls, 0);
    expect(find.text('Necesitas conexión para guardar los cambios'),
        findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Fictional notes'), findsOneWidget);
    offline = false;
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    expect(editor.calls, 1);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Cambios guardados'), findsOneWidget);
  });

  testWidgets(
      'slow activity edit allows closing and handles late confirmation safely',
      (tester) async {
    final ack = Completer<void>();
    final editor = ControlledEditor(() => ack.future);
    await activity(tester, editor, () async => false);
    await tester.tap(find.text('Guardar cambios'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(find.text('El guardado está tardando. Espera un momento'),
        findsOneWidget);
    expect(find.text('Esperando confirmación…'), findsOneWidget);
    expect(editor.calls, 1);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    ack.complete();
    await tester.pumpAndSettle();
    expect(find.text('Cambios guardados'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
