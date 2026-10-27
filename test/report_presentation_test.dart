import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/models/user_model.dart';
import 'package:micomunidad/widgets/current_report_author_name.dart';
import 'package:micomunidad/widgets/report_presentation.dart';
import 'package:micomunidad/widgets/expandable_description.dart';

const example = <String, dynamic>{
  'title': 'Luminaria apagada',
  'status': 'pendiente',
  'moderationStatus': 'aprobado',
  'priority': 'alta',
  'category': 'iluminacion',
  'location': 'Pasaje de demostración',
  'description': 'Una descripción que solo se lee al ampliar el reporte.',
  'createdBy': 'demo-owner',
  'createdByName': 'Nombre de demostración',
};

AppUser owner(String name) => AppUser(
    userId: 'demo-owner',
    email: 'demo@example.com',
    nombre: name,
    role: UserRole.admin,
    approvalStatus: 'aprobado',
    joinDate: DateTime(2026),
    communityId: 'demo',
    createdAt: DateTime(2026));

Future<void> present(WidgetTester tester, Widget child,
    {double width = 412, double scale = 1}) async {
  tester.view.physicalSize = Size(width, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: Scaffold(
        body: SingleChildScrollView(
            padding: const EdgeInsets.all(16), child: child)),
  ));
}

void main() {
  testWidgets('edit action does not add blank space below a short title',
      (tester) async {
    Widget card({VoidCallback? onEdit}) => ReportPreviewCard(
        data: example,
        status: 'pendiente',
        author: const Text('Autor de demostración'),
        onOpen: () {},
        onEdit: onEdit);

    await present(tester, card());
    final plainHeight = tester.getSize(find.byType(ReportPreviewCard)).height;
    final plainGap =
        tester.getTopLeft(find.text(example['description'] as String)).dy -
            tester.getBottomLeft(find.text(example['title'] as String)).dy;

    var edits = 0;
    await present(tester, card(onEdit: () => edits++));
    final editGap =
        tester.getTopLeft(find.text(example['description'] as String)).dy -
            tester.getBottomLeft(find.text(example['title'] as String)).dy;
    expect(editGap, plainGap);
    expect(editGap, 12);
    expect(tester.getSize(find.byType(ReportPreviewCard)).height, plainHeight);
    final editRect = tester.getRect(find.byTooltip('Editar mi reporte'));
    expect(editRect.width, greaterThanOrEqualTo(48));
    expect(editRect.height, greaterThanOrEqualTo(48));
    // The edge of the touch target also edits instead of opening the report.
    await tester.tapAt(editRect.bottomRight - const Offset(2, 2));
    expect(edits, 1);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'long title stays within two lines clear of the pencil at text scale $scale',
        (tester) async {
      final title =
          ('Reporte sobre iluminación en el acceso peatonal ' * 5).trim();
      var opens = 0;
      var edits = 0;
      await present(
          tester,
          ReportPreviewCard(
              data: {...example, 'title': title},
              status: 'pendiente',
              author: const Text('Autor de demostración'),
              onOpen: () => opens++,
              onEdit: () => edits++),
          width: 320,
          scale: scale);
      final titleFinder = find.text(title);
      final text = tester.widget<Text>(titleFinder);
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
      final titleRect = tester.getRect(titleFinder);
      final editRect = tester.getRect(find.byTooltip('Editar mi reporte'));
      expect(titleRect.height, greaterThan(48));
      expect(titleRect.right, lessThanOrEqualTo(editRect.left));
      expect(
          tester.getTopLeft(find.text(example['description'] as String)).dy -
              titleRect.bottom,
          12);
      await tester.tap(find.byTooltip('Editar mi reporte'));
      expect(edits, 1);
      expect(opens, 0);
      await tester.tap(titleFinder);
      expect(opens, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'preview keeps title, short description, state, priority, author and location',
      (tester) async {
    var opens = 0;
    var edits = 0;
    await present(
        tester,
        ReportPreviewCard(
            data: example,
            status: 'pendiente',
            author: const Text('Nombre actual'),
            onOpen: () => opens++,
            onEdit: () => edits++));
    for (final text in [
      'Luminaria apagada',
      'Por atender',
      'Prioridad alta',
      'Nombre actual',
      'Pasaje de demostración'
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    final description = find.text(example['description'] as String);
    expect(description, findsOneWidget);
    expect(tester.widget<Text>(description).maxLines, 2);
    expect(tester.widget<Text>(description).overflow, TextOverflow.ellipsis);
    expect(find.text('Descripción'), findsNothing);
    expect(find.text('Iluminación'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.text('Luminaria apagada'));
    expect(opens, 1);
    await tester.tap(find.byTooltip('Editar mi reporte'));
    expect(edits, 1);
    expect(opens, 1);
  });

  testWidgets(
      'an other-author card without an edit callback never displays a pencil',
      (tester) async {
    await present(
        tester,
        ReportPreviewCard(
            data: example,
            status: 'pendiente',
            author: const Text('Otro autor'),
            onOpen: () {}));
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byTooltip('Editar mi reporte'), findsNothing);
  });

  final states = <String, (String, Color, Color)>{
    'en_revision': (
      'En revisión',
      const Color(0xFFECEFF1),
      const Color(0xFF455A64)
    ),
    'pendiente': (
      'Por atender',
      const Color(0xFFFFF3CD),
      const Color(0xFF795600)
    ),
    'en_proceso': (
      'En proceso',
      const Color(0xFFE4EFFB),
      const Color(0xFF285A86)
    ),
    'resuelto': ('Resuelto', const Color(0xFFD8EEDD), const Color(0xFF236344)),
    'rechazado': (
      'Rechazado',
      const Color(0xFFF9E5E3),
      const Color(0xFF9F3832)
    ),
  };
  for (final entry in states.entries) {
    testWidgets(
        '${entry.value.$1} has the agreed soft state color and readable label',
        (tester) async {
      await present(tester, ReportStatusBadge(status: entry.key));
      final label = find.text(entry.value.$1);
      expect(label, findsOneWidget);
      expect(tester.widget<Text>(label).style?.color, entry.value.$3);
      final container = tester.widget<Container>(find.descendant(
          of: find.byType(ReportStatusBadge),
          matching: find.byType(Container)));
      expect((container.decoration as BoxDecoration).color, entry.value.$2);
      // Normal-size label contrast remains readable without relying on color alone.
      final contrast = (entry.value.$2.computeLuminance() + .05) /
          (entry.value.$3.computeLuminance() + .05);
      expect(contrast, greaterThanOrEqualTo(4.5));
    });
  }

  for (final priority in ['alta', 'media', 'baja']) {
    testWidgets(
        'priority $priority uses a flag and text, with no second colored badge',
        (tester) async {
      await present(tester, ReportPriorityLabel(priority: priority));
      final label = find.text('Prioridad $priority');
      expect(label, findsOneWidget);
      expect(find.byIcon(Icons.outlined_flag), findsOneWidget);
      final scope = find.byType(ReportPriorityLabel);
      expect(find.descendant(of: scope, matching: find.byType(Container)),
          findsNothing);
      expect(find.descendant(of: scope, matching: find.byType(Chip)),
          findsNothing);
      final color = tester.widget<Text>(label).style!.color!;
      expect(
          (1.05) / (color.computeLuminance() + .05), greaterThanOrEqualTo(4.5));
    });
  }

  test(
      'pending moderation stays En revisión even if an operational state is present',
      () {
    expect(
        ReportVisuals.displayStatus({
          ...example,
          'moderationStatus': 'pendiente',
          'status': 'en_proceso'
        }),
        'en_revision');
    expect(ReportVisuals.displayStatus({...example, 'moderationStatus': null}),
        'en_revision');
    expect(ReportVisuals.displayStatus({...example, 'status': 'en_revision'}),
        'pendiente');
    expect(
        ReportVisuals.displayStatus(
            {...example, 'moderationStatus': 'rechazado'}),
        'rechazado');
  });

  testWidgets(
      'expanded report orders metadata before full description and adds no progress percentage',
      (tester) async {
    await present(
        tester,
        ReportInformation(data: {
          ...example,
          'createdAt': Timestamp.fromDate(DateTime(2026, 10, 25))
        }));
    for (final text in [
      'Por atender',
      'Prioridad alta',
      'Iluminación',
      'Reportado por Nombre de demostración',
      'Pasaje de demostración',
      'Registrado el 25/10/2026',
      example['description'] as String
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(
        tester.getTopLeft(find.text('Registrado el 25/10/2026')).dy,
        lessThan(
            tester.getTopLeft(find.text(example['description'] as String)).dy));
    expect(find.text('Luminaria apagada'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('own author name prefix stays current after a profile update',
      (tester) async {
    await present(
        tester,
        ReportInformation(
            data: example,
            reportId: 'demo-report',
            user: owner('Nombre anterior')));
    expect(find.text('Reportado por Nombre anterior'), findsOneWidget);
    final original = tester.element(find.byType(CurrentReportAuthorName));
    await present(
        tester,
        ReportInformation(
            data: example,
            reportId: 'demo-report',
            user: owner('Nombre actualizado')));
    expect(find.text('Reportado por Nombre actualizado'), findsOneWidget);
    expect(
        tester.element(find.byType(CurrentReportAuthorName)), same(original));
    expect(find.textContaining('demo@example.com'), findsNothing);
  });

  testWidgets('rejected report keeps its reason in the full detail',
      (tester) async {
    await present(
        tester,
        ReportInformation(data: {
          ...example,
          'moderationStatus': 'rechazado',
          'moderationReason': 'Existe otro reporte del mismo problema.'
        }));
    expect(find.text('Rechazado'), findsOneWidget);
    expect(find.text('Motivo del rechazo'), findsOneWidget);
    expect(
        find.text('Existe otro reporte del mismo problema.'), findsOneWidget);
  });

  testWidgets('long description keeps Leer más and Leer menos', (tester) async {
    final description =
        List.generate(20, (i) => 'Línea ficticia $i.').join('\n');
    await present(tester,
        ReportInformation(data: {...example, 'description': description}));
    expect(tester.widget<Text>(find.text(description)).maxLines, 4);
    await tester.tap(find.text('Leer más'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text(description)).maxLines, isNull);
    expect(find.text('Leer menos'), findsOneWidget);
    expect(find.byType(ExpandableDescription), findsOneWidget);
  });

  for (final width in [320.0, 412.0, 600.0]) {
    for (final scale in [1.0, 1.6, 2.0]) {
      testWidgets(
          'report cards and details fit width $width at text scale $scale',
          (tester) async {
        final long = {
          ...example,
          'title':
              'Reporte ficticio sobre iluminación y acceso peatonal en el espacio comunitario',
          'location':
              'Ubicación de demostración con referencias suficientemente largas para ajustar el texto',
          'createdByName':
              'Nombre ficticio con varios apellidos para comprobar la distribución',
          'description': 'Descripción completa para leer en el detalle. ' * 12
        };
        await present(
            tester,
            Column(children: [
              ReportPreviewCard(
                  data: long,
                  status: 'en_proceso',
                  author: Text(long['createdByName'] as String),
                  onOpen: () {},
                  onEdit: () {}),
              ReportInformation(data: long),
            ]),
            width: width,
            scale: scale);
        expect(tester.takeException(), isNull);
        expect(find.text('Prioridad alta'), findsNWidgets(2));
      });
    }
  }
}
