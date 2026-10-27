import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/widgets/content_information.dart';

Future<void> showInformation(
    WidgetTester tester, String collection, Map<String, dynamic> data,
    {double scale = 1}) async {
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: Scaffold(
        body: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: ContentInformation(collection: collection, data: data))),
  ));
}

void main() {
  testWidgets(
      'project keeps full description available behind read more without another title',
      (tester) async {
    final description =
        List.generate(12, (i) => 'Demo description line $i.').join('\n');
    await showInformation(tester, 'projects', {
      'title': 'Title stays in the sheet',
      'description': description,
      'location': 'Demo hall',
      'status': 'en_proceso',
      'progress': 80,
      'createdAt': Timestamp.now()
    });
    expect(find.text(description), findsOneWidget);
    expect(tester.widget<Text>(find.text(description)).maxLines, 4);
    expect(find.text('Leer más'), findsOneWidget);
    await tester.tap(find.text('Leer más'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text(description)).maxLines, isNull);
    expect(find.text('Leer menos'), findsOneWidget);
    expect(find.text('Demo hall'), findsOneWidget);
    expect(find.text('Ubicación'), findsNothing);
    expect(find.text('Descripción'), findsOneWidget);
    expect(find.byIcon(Icons.location_on_outlined), findsOneWidget);
    expect(find.text('En proceso'), findsOneWidget);
    expect(find.text('80 % de avance'), findsOneWidget);
    expect(find.byType(Chip), findsNothing);
    final locationRow =
        find.ancestor(of: find.text('Demo hall'), matching: find.byType(Row));
    expect(locationRow, findsOneWidget);
    expect(find.descendant(of: locationRow, matching: find.byType(Text)),
        findsOneWidget);
    expect(find.text('Title stays in the sheet'), findsNothing);
    expect(find.text('Registrado'), findsNothing);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        .8);
    expect(tester.getTopLeft(find.text('Demo hall')).dy,
        lessThan(tester.getTopLeft(find.text(description)).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'approved report shows category with accents, priority and registration date',
      (tester) async {
    await showInformation(tester, 'reports', {
      'description': 'Demo report description',
      'location': 'Demo path',
      'status': 'en_proceso',
      'moderationStatus': 'aprobado',
      'category': 'iluminacion',
      'priority': 'alta',
      'createdAt': Timestamp.fromDate(DateTime(2026, 11, 7, 18, 30))
    });
    for (final text in [
      'Demo report description',
      'Demo path',
      'En proceso',
      'Iluminación',
      'Prioridad alta',
      'Registrado el 07/11/2026'
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.textContaining('% de avance'), findsNothing);
    expect(find.byType(Chip), findsNothing);
  });

  testWidgets('agenda shows complete description, location, full date and time',
      (tester) async {
    await showInformation(tester, 'events', {
      'description': 'Full demo agenda description',
      'location': 'Demo meeting hall',
      'eventDate': Timestamp.fromDate(DateTime(2026, 11, 7, 18, 30)),
      'status': 'pendiente',
      'progress': 20
    });
    for (final text in [
      'Full demo agenda description',
      'Demo meeting hall',
      '07/11/2026 • 18:30'
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.byType(Chip), findsNothing);
    expect(find.text('Fecha y hora'), findsNothing);
    expect(find.text('Descripción'), findsOneWidget);
    expect(find.text('Ubicación'), findsNothing);
    expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);
    expect(find.text('Leer más'), findsNothing);
  });

  for (final collection in ['projects', 'reports', 'events']) {
    testWidgets(
        '$collection with absent or whitespace values adds no placeholders',
        (tester) async {
      await showInformation(tester, collection, {
        'description': '  ',
        'location': '\n',
        'createdAt': 'bad-date',
        'eventDate': 'bad-date',
        'progress': double.nan
      });
      expect(find.byType(Text), findsNothing);
      expect(find.byType(Chip), findsNothing);
      expect(find.byType(Icon), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'only whitelisted content fields are visible; identifiers and internal notes are not',
      (tester) async {
    await showInformation(tester, 'projects', {
      'description': 'Safe demo description',
      'uid': 'not-for-display-uid',
      'email': 'internal@example.com',
      'dni': '00000001',
      'createdBy': 'not-for-display-creator',
      'internalNotes': 'not-for-display-notes',
      'url': 'https://example.com/not-for-display'
    });
    expect(find.text('Safe demo description'), findsOneWidget);
    for (final text in [
      'not-for-display-uid',
      'internal@example.com',
      '00000001',
      'not-for-display-creator',
      'not-for-display-notes',
      'https://example.com/not-for-display'
    ]) {
      expect(find.text(text), findsNothing);
    }
  });

  testWidgets(
      'unknown collection does not accidentally expose another document',
      (tester) async {
    await showInformation(tester, 'users',
        {'description': 'Not for display', 'location': 'Not for display'});
    expect(find.byType(Text), findsNothing);
  });

  for (final status in ['pendiente', 'en_proceso', 'finalizado']) {
    testWidgets('project state $status is readable metadata', (tester) async {
      await showInformation(tester, 'projects', {'status': status});
      expect(
          find.text({
            'pendiente': 'Pendiente',
            'en_proceso': 'En proceso',
            'finalizado': 'Finalizado'
          }[status]!),
          findsOneWidget);
    });
  }

  for (final status in ['pendiente', 'en_revision', 'en_proceso', 'resuelto']) {
    testWidgets('report state $status is readable metadata', (tester) async {
      await showInformation(tester, 'reports',
          {'status': status, 'moderationStatus': 'aprobado'});
      expect(
          find.text({
            'pendiente': 'Por atender',
            'en_revision': 'Por atender',
            'en_proceso': 'En proceso',
            'resuelto': 'Resuelto'
          }[status]!),
          findsOneWidget);
    });
  }

  testWidgets(
      'zero progress is kept and out of range display is bounded without mutating data',
      (tester) async {
    for (final value in [0, -5, 120]) {
      final data = <String, dynamic>{'progress': value};
      await showInformation(tester, 'projects', data);
      expect(find.text('${value.clamp(0, 100)} % de avance'), findsOneWidget);
      expect(data['progress'], value);
    }
  });

  testWidgets('all detail types wrap safely at narrow widths and large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final collection in ['projects', 'reports', 'events']) {
      await showInformation(
          tester,
          collection,
          {
            'description': 'Demo full description ' * 20,
            'location':
                'Demo location with enough text to wrap across several lines',
            'status': 'resuelto',
            'moderationStatus': 'aprobado',
            'category': 'iluminacion',
            'priority': 'alta',
            'progress': 80,
            'eventDate': Timestamp.fromDate(DateTime(2026, 11, 7, 18, 30))
          },
          scale: 1.6);
      if (collection == 'reports') {
        expect(find.text('Resuelto'), findsOneWidget);
        expect(find.text('Iluminación'), findsOneWidget);
        expect(find.text('Prioridad alta'), findsOneWidget);
      }
      expect(find.text('Descripción'), findsOneWidget);
      final heading = find.text('Descripción');
      final description = find.text(('Demo full description ' * 20).trim());
      expect(tester.getTopLeft(heading).dx, tester.getTopLeft(description).dx);
      expect(tester.getBottomLeft(heading).dy,
          lessThan(tester.getTopLeft(description).dy));
      expect(find.text('Ubicación'), findsNothing);
      expect(find.byType(Chip), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
