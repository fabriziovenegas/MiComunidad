import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/models/project_dates.dart';
import 'package:micomunidad/services/pending_content_service.dart';
import 'package:micomunidad/services/content_delivery.dart';
import 'package:micomunidad/widgets/project_dates_fields.dart';

void main() {
  final start = Timestamp.fromDate(DateTime(2026, 11, 1));
  final end = Timestamp.fromDate(DateTime(2026, 11, 30));
  Map<String, dynamic> fields() => {
        'title': 'Proyecto ficticio',
        'description': 'Descripción',
        'location': '',
        'progress': 0,
        'status': 'pendiente'
      };
  for (final dates in [
    <String, dynamic>{},
    {'startDate': start},
    {'expectedEndDate': end},
    {'startDate': start, 'expectedEndDate': end}
  ]) {
    test('optional dates $dates preserve old pending format and round trip',
        () {
      final item = PendingContent(
          id: 'project',
          collection: 'projects',
          userId: 'owner',
          fields: {...fields(), ...dates});
      item.validate();
      expect(PendingContent.fromJson(item.toJson()).fields, item.fields);
    });
  }
  test('invalid order or types are rejected', () {
    expect(ProjectDates.valid({'startDate': end, 'expectedEndDate': start}),
        false);
    expect(ProjectDates.valid({'startDate': '2026-11-01'}), false);
    expect(ProjectDates.valid({'startDate': start, 'expectedEndDate': start}),
        true);
  });
  testWidgets(
      'both dates are optional, removable and validated on a narrow large-text form',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    DateTime? from = DateTime(2026, 11, 30), to = DateTime(2026, 11, 1);
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(MaterialApp(
        builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(2)),
            child: child!),
        home: Scaffold(
            body: SingleChildScrollView(
                child: Form(
                    key: form,
                    child: StatefulBuilder(
                        builder: (context, setState) => ProjectDatesFields(
                            start: from,
                            end: to,
                            enabled: true,
                            onChanged: (a, b) => setState(() {
                                  from = a;
                                  to = b;
                                }))))))));
    expect(form.currentState!.validate(), false);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Quitar Inicio'), findsNothing);
    await tester.tap(find.text('Fechas del proyecto'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Quitar Inicio'));
    await tester.pumpAndSettle();
    expect(from, isNull);
    expect(form.currentState!.validate(), true);
    await tester.tap(find.byTooltip('Quitar Fin previsto'));
    await tester.pumpAndSettle();
    expect(to, isNull);
    expect(form.currentState!.validate(), true);
  });
  testWidgets(
      'date section starts folded and retains dates and validation when folded again',
      (tester) async {
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: Form(
      key: form,
      child: ProjectDatesFields(
          start: DateTime(2026, 11, 1),
          end: DateTime(2026, 11, 30),
          enabled: true,
          onChanged: (_, __) {}),
    )))));
    expect(find.textContaining('Inicio: 01/11/2026'), findsOneWidget);
    expect(find.byTooltip('Quitar Inicio'), findsNothing);
    await tester.tap(find.text('Fechas del proyecto'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Quitar Inicio'), findsOneWidget);
    await tester.tap(find.text('Fechas del proyecto'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Quitar Inicio'), findsNothing);
    expect(form.currentState!.validate(), true);
    expect(find.textContaining('30/11/2026'), findsOneWidget);
  });
  test('dated project survives offline restart and sends once', () async {
    final dir = await Directory.systemTemp.createTemp('project-dates-test-');
    try {
      final db = FakeFirebaseFirestore();
      await db
          .doc('users/owner')
          .set({'role': 'admin', 'approvalStatus': 'aprobado'});
      var offline = true;
      final actual =
          FirebaseContentDelivery(firestore: db, currentUserId: () => 'owner');
      final delivery = _OfflineDelivery(() => offline, actual);
      PendingContentService queue() => PendingContentService(
          directory: () async => dir,
          currentUserId: () => 'owner',
          delivery: delivery);
      final result = await queue().submit(
          id: 'dated-project',
          collection: 'projects',
          expectedUserId: 'owner',
          fields: {...fields(), 'startDate': start, 'expectedEndDate': end});
      expect(result.state.name, 'queued');
      final reopened = queue();
      expect((await reopened.pendingFor('owner')).single.fields['startDate'],
          start);
      offline = false;
      await reopened.processPending();
      await reopened.processPending();
      final saved = (await db.doc('projects/dated-project').get()).data()!;
      expect(saved['startDate'], start);
      expect(saved['expectedEndDate'], end);
      expect((await db.collection('projects').get()).docs, hasLength(1));
      expect(await reopened.pendingFor('owner'), isEmpty);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}

class _OfflineDelivery implements ContentDelivery {
  _OfflineDelivery(this.offline, this.actual);
  final bool Function() offline;
  final ContentDelivery actual;
  @override
  Future<void> deliver(PendingContent item) async {
    if (offline()) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    await actual.deliver(item);
  }
}
