import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:micomunidad/widgets/attachment_information.dart';
import 'package:micomunidad/widgets/agenda_presentation.dart';
import 'package:micomunidad/widgets/image_gallery_screen.dart';

void main() {
  testWidgets('photo viewer info follows the selected image', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: ImageGalleryScreen(
      urls: const ['gs://fictional/a', 'gs://fictional/b'],
      information: {
        'gs://fictional/a': (_) =>
            const AlertDialog(content: Text('First photo details')),
        'gs://fictional/b': (_) =>
            const AlertDialog(content: Text('Second photo details')),
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Información del archivo'));
    await tester.pumpAndSettle();
    expect(find.text('First photo details'), findsOneWidget);
    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pumpAndSettle();
    final page = tester.widget<PageView>(find.byType(PageView));
    page.controller!.jumpToPage(1);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Información del archivo'));
    await tester.pumpAndSettle();
    expect(find.text('Second photo details'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'displays current name and upload date including year, not raw uid',
      (tester) async {
    final name = Completer<String?>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AttachmentInformationDialog(
                name: 'example.pdf',
                createdAt: Timestamp.fromDate(DateTime(2026, 10, 30, 14, 5)),
                loadName: () => name.future))));
    expect(find.text('Consultando…'), findsOneWidget);
    name.complete('Nombre actualizado');
    await tester.pumpAndSettle();
    expect(find.text('Nombre actualizado'), findsOneWidget);
    expect(find.text('30/10/2026 · 14:05'), findsOneWidget);
  });
  testWidgets(
      'legacy missing data or offline never hides the dialog or invents values',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AttachmentInformationDialog(
                name: '',
                createdAt: null,
                loadName: () async => throw StateError('private')))));
    await tester.pumpAndSettle();
    expect(find.text('No disponible'), findsNWidgets(2));
    expect(find.textContaining('private'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'document info and delete remain separate and fit narrow text scale $scale',
        (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var info = 0, opened = 0, deleted = 0;
      await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: Scaffold(
              body: AgendaDocumentTile(
                  name: 'a' * 180 + '.pdf',
                  isPdf: true,
                  onOpen: () => opened++,
                  onInfo: () => info++,
                  onDelete: () => deleted++))));
      await tester.tap(find.byTooltip('Información del archivo'));
      expect(info, 1);
      expect(opened, 0);
      expect(deleted, 0);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('gallery without attached metadata stays compatible',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: ImageGalleryScreen(urls: [])));
    expect(find.byTooltip('Información del archivo'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
