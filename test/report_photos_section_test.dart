import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/services/file_service.dart';
import 'package:micomunidad/services/photo_picker.dart';
import 'package:micomunidad/widgets/report_photos_section.dart';

SelectedUpload photo(String name) =>
    SelectedUpload(PlatformFile(name: name, size: 8, bytes: Uint8List(8)));

void main() {
  testWidgets('add up to three, remove one and add another', (tester) async {
    var selected = <SelectedUpload>[];
    var picks = 0;
    final picking = <bool>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
      builder: (context, update) => ReportPhotosSection(
        photos: selected,
        onChanged: (photos) => update(() => selected = photos),
        onPickingChanged: picking.add,
        pick: (_) async => PhotoSelection([photo('photo-${++picks}.png')]),
      ),
    ))));
    expect(find.text('0 de 3'), findsOneWidget);
    for (var i = 1; i <= 3; i++) {
      await tester.tap(find.text('Añadir fotografía'));
      await tester.pumpAndSettle();
      expect(find.text('$i de 3'), findsOneWidget);
    }
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    await tester.tap(find.byTooltip('Quitar photo-2.png'));
    await tester.pumpAndSettle();
    expect(find.text('2 de 3'), findsOneWidget);
    await tester.tap(find.text('Añadir fotografía'));
    await tester.pumpAndSettle();
    expect(selected.map((p) => p.name),
        ['photo-1.png', 'photo-3.png', 'photo-4.png']);
    expect(picking, [true, false, true, false, true, false, true, false]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('batch selection respects remaining capacity', (tester) async {
    var selected = [photo('first.png')];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
      builder: (context, update) => ReportPhotosSection(
        photos: selected,
        onChanged: (photos) => update(() => selected = photos),
        onPickingChanged: (_) {},
        pick: (_) async => PhotoSelection(
            [photo('second.png'), photo('third.png'), photo('fourth.png')]),
      ),
    ))));
    await tester.tap(find.text('Añadir fotografía'));
    await tester.pumpAndSettle();
    expect(
        selected.map((p) => p.name), ['first.png', 'second.png', 'third.png']);
    expect(find.text('3 de 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long filenames fit narrow screens with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
      child: SingleChildScrollView(
          child: ReportPhotosSection(
        photos: [photo('${'long-name-' * 20}.png')],
        onChanged: (_) {},
        onPickingChanged: (_) {},
      )),
    ))));
    expect(tester.takeException(), isNull);
  });
}
