import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/screens/neighbor/projects_screen.dart';

void main() {
  const labels = ['Todos', 'Pendiente', 'En proceso', 'Finalizado'];

  Widget layout({bool admin = true, ValueChanged<String>? onSelected}) =>
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(18),
            child: ProjectFiltersLayout(
              selectedFilter: 'todos',
              onSelected: onSelected ?? (_) {},
              archivedButton: admin
                  ? OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.archive_outlined),
                      label: const Text('Archivados'),
                    )
                  : null,
            ),
          ),
        ),
      );

  for (final width in [320.0, 400.0, 600.0]) {
    testWidgets('painted filters fill equal columns at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(layout());
      final chips = [
        for (final label in labels) find.widgetWithText(FilterChip, label),
      ];
      final bounds = chips.map(tester.getRect).toList();
      final surfaces = [
        for (final chip in chips)
          tester.getRect(find.descendant(
            of: chip,
            matching: find.byType(Material),
          )),
      ];
      for (var i = 0; i < 4; i++) {
        expect(bounds[i].width, closeTo((width - 36 - 12) / 2, 0.01));
        expect(surfaces[i].width, closeTo(bounds[i].width, 0.01));
        expect(surfaces[i].height, closeTo(surfaces[0].height, 0.01));
        expect(bounds[i].height, closeTo(bounds[0].height, 0.01));
        expect(bounds[i].height, greaterThanOrEqualTo(48));
        expect(surfaces[i].height, lessThan(48));
      }
      expect(bounds[0].top, bounds[1].top);
      expect(bounds[2].top, bounds[3].top);
      expect(bounds[0].left, bounds[2].left);
      expect(bounds[1].left - bounds[0].right, closeTo(12, 0.01));
      expect(bounds[2].top - bounds[0].bottom, closeTo(12, 0.01));
      final archive = tester.getRect(find.byType(OutlinedButton));
      final heading = tester.getRect(find.text('Filtros'));
      expect(heading.center.dy, closeTo(archive.center.dy, 0.01));
      expect(archive.right, closeTo(bounds[1].right, 0.01));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('selection forwards unchanged values; no extra icons',
      (tester) async {
    final values = <String>[];
    await tester.pumpWidget(layout(onSelected: values.add));
    for (final label in labels) {
      await tester.tap(find.widgetWithText(FilterChip, label));
      await tester.pump();
    }
    expect(values, ['todos', 'pendiente', 'en_proceso', 'finalizado']);
    expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Todos'))
            .selected,
        isTrue);
    expect(
        find.descendant(
            of: find.byType(FilterChip), matching: find.byType(Icon)),
        findsNothing);
  });

  testWidgets('no archived action supplied for neighbor', (tester) async {
    await tester.pumpWidget(layout(admin: false));
    expect(find.text('Archivados'), findsNothing);
    expect(find.byType(FilterChip), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });
}
