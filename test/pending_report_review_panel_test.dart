import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/widgets/pending_report_review_panel.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('long text fits narrow screen at text scale $scale',
        (tester) async {
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opened = 0;
      var approved = 0;
      var rejected = 0;
      final title = List.filled(15, 'Reporte de prueba').join(' ');
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: Scaffold(
            body: SingleChildScrollView(
                child: PendingReportReviewPanel(
          children: [
            PendingReportReviewRow(
              title: title,
              description: List.filled(20, 'Descripción de prueba').join(' '),
              onOpen: () => opened++,
              onReject: () => rejected++,
              onApprove: () => approved++,
            ),
            PendingReportReviewRow(
              title: 'Otro reporte',
              description: '',
              onOpen: () {},
              onReject: () {},
              onApprove: () {},
            ),
          ],
        ))),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('2'), findsOneWidget);
      await tester.tap(find.byTooltip('Aprobar').first);
      await tester.tap(find.byTooltip('Rechazar').first);
      expect(approved, 1);
      expect(rejected, 1);
      expect(opened, 0);
      await tester.tap(find.text(title));
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
