import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/services/map_point_writer.dart';
import 'package:micomunidad/widgets/map_point_form.dart';
import 'package:micomunidad/widgets/upload_error_notice.dart';

Future<void> open(
    WidgetTester tester, Future<void> Function(String, String) save,
    {Future<bool> Function()? offline}) async {
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                  onPressed: () => showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => MapPointForm(
                          onSave: save,
                          isOffline: offline ?? () async => false)),
                  child: const Text('Abrir'))))));
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(dismissUploadError);
  testWidgets('empty and overlong names do not submit or close',
      (tester) async {
    var calls = 0;
    await open(tester, (_, __) async {
      calls++;
    });
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('El nombre es obligatorio.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'a' * 161);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
  testWidgets('offline retains input and never calls save; reconnect retries',
      (tester) async {
    var offline = true;
    var calls = 0;
    await open(tester, (title, description) async {
      calls++;
      expect(title, 'Referencia ficticia');
      expect(description, 'Notas');
    }, offline: () async => offline);
    await tester.enterText(
        find.byType(TextFormField).first, 'Referencia ficticia');
    await tester.enterText(find.byType(TextFormField).last, 'Notas');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(
        find.text('Necesitas conexión para guardar el punto'), findsOneWidget);
    expect(find.text('Referencia ficticia'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    offline = false;
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets(
      'failed write retains fields, hides private error and permits retry',
      (tester) async {
    var calls = 0;
    await open(tester, (_, __) async {
      if (++calls == 1) throw StateError('private');
    });
    await tester.enterText(find.byType(TextFormField).first, 'Referencia');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No se pudo guardar el punto.'), findsOneWidget);
    expect(find.text('Referencia'), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets(
      'slow confirmation warns, prevents concurrent saves and closes only on acknowledgement',
      (tester) async {
    final ack = Completer<void>();
    var calls = 0;
    await open(tester, (_, __) {
      calls++;
      return ack.future;
    });
    await tester.enterText(find.byType(TextFormField).first, 'Referencia');
    final submit =
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed!;
    submit();
    submit();
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(calls, 1);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byKey(const ValueKey('save-warning-notice')), findsOneWidget);
    expect(find.text('Esperando confirmación…'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cerrar'))
            .onPressed,
        isNotNull);
    ack.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test('stable id retries leave exactly one point and preserve createdAt',
      () async {
    final db = FakeFirebaseFirestore();
    await db
        .doc('users/admin')
        .set({'role': 'admin', 'approvalStatus': 'aprobado'});
    final writer = MapPointWriter(firestore: db, currentUserId: () => 'admin');
    Future<void> save() => writer.save(
        id: 'fictional-point',
        userId: 'admin',
        title: 'Referencia',
        description: 'Notas',
        latitude: 0.1,
        longitude: 0.2);
    await save();
    final before = (await db.doc('mapPoints/fictional-point').get()).data()!;
    await save();
    expect((await db.collection('mapPoints').get()).docs.length, 1);
    expect((await db.doc('mapPoints/fictional-point').get()).data(), before);
    await expectLater(
        writer.save(
            id: 'fictional-point',
            userId: 'admin',
            title: 'Otro',
            description: 'Notas',
            latitude: 0.1,
            longitude: 0.2),
        throwsStateError);
    expect((await db.doc('mapPoints/fictional-point').get()).data(), before);
  });
  for (final role in ['vecino', 'pending', 'signed-out']) {
    test('writer rejects $role without creating points', () async {
      final db = FakeFirebaseFirestore();
      await db.doc('users/person').set({
        'role': role == 'pending' ? 'admin' : role,
        'approvalStatus': role == 'pending' ? 'pendiente' : 'aprobado'
      });
      final writer = MapPointWriter(
          firestore: db,
          currentUserId: () => role == 'signed-out' ? null : 'person');
      await expectLater(
          writer.save(
              id: 'fictional-point',
              userId: 'person',
              title: 'Referencia',
              description: '',
              latitude: 0,
              longitude: 0),
          throwsA(isA<FirebaseException>()));
      expect((await db.collection('mapPoints').get()).docs, isEmpty);
    });
  }
}
