import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/services/pending_report_service.dart';
import 'package:micomunidad/widgets/pending_reports_notice.dart';
import 'pending_report_service_test.dart'
    show LocalDelivery, reportFields, noConnection;

void main() {
  late Directory directory;
  late LocalDelivery delivery;
  late PendingReportService service;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pending-notice-test-');
    delivery = LocalDelivery()
      ..beforeReport = (_) async => throw noConnection();
    service = PendingReportService(
        directory: () => Future.value(directory),
        currentUserId: () => 'owner',
        delivery: delivery);
  });
  tearDown(() async {
    final path = await directory.resolveSymbolicLinks();
    expect(path, contains('pending-notice-test-'));
    await Directory(path).delete(recursive: true);
  });
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
    }
    await tester.pumpAndSettle();
  }

  Widget app({String owner = 'owner'}) => MaterialApp(
          home: Scaffold(
              body: ListView(children: [
        PendingReportsNotice(userId: owner, service: service)
      ])));

  testWidgets(
      'shows saved report after reopening and retry removes it after confirmation',
      (tester) async {
    await tester.runAsync(() => service.submit(
        id: 'pending-one', expectedUserId: 'owner', fields: reportFields));
    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.text('1 reporte pendiente de envío'), findsOneWidget);
    await tester.tap(find.text('1 reporte pendiente de envío'));
    await tester.pumpAndSettle();
    expect(find.text(reportFields['title']!), findsOneWidget);
    expect(find.text('Se enviará cuando tengas conexión y abras la app.'),
        findsOneWidget);
    delivery.beforeReport = null;
    await tester.tap(find.text('Reintentar'));
    await settle(tester);
    expect(find.text('1 reporte pendiente de envío'), findsNothing);
    expect(delivery.reports, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('does not show another account saved reports', (tester) async {
    await tester.runAsync(() => service.submit(
        id: 'pending-one', expectedUserId: 'owner', fields: reportFields));
    await tester.pumpWidget(app(owner: 'other'));
    await settle(tester);
    expect(find.text('1 reporte pendiente de envío'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('newly saved report updates an already open screen',
      (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.text('1 reporte pendiente de envío'), findsNothing);
    await tester.runAsync(() => service.submit(
        id: 'pending-one', expectedUserId: 'owner', fields: reportFields));
    await settle(tester);
    expect(find.text('1 reporte pendiente de envío'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
