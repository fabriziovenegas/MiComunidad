// Test-only SDK doubles: no network or real security rules are used.
// ignore_for_file: subtype_of_sealed_class, must_be_immutable
import 'dart:io';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:micomunidad/core/theme/app_theme.dart';
import 'package:micomunidad/screens/admin/admin_dashboard_screen.dart';
import 'package:micomunidad/widgets/admin_upcoming_event_card.dart';
import 'admin_dashboard_greeting_test.dart' show adminUser;

class UnavailableAgenda extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      path == 'events' ? _UnavailableCollection() : super.collection(path);
}

class _UnavailableCollection
    implements CollectionReference<Map<String, dynamic>> {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (const [#where, #orderBy, #limit].contains(invocation.memberName)) {
      return this;
    }
    if (invocation.memberName == #snapshots) {
      return Stream<QuerySnapshot<Map<String, dynamic>>>.error(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));
    }
    throw UnimplementedError();
  }
}

final start = DateTime(2026, 11, 4, 10);
Future<void> event(FakeFirebaseFirestore db, String id, DateTime date,
        {String? title, String location = 'Local de prueba'}) =>
    db.doc('events/$id').set({
      'title': title ?? id,
      'location': location,
      'eventDate': Timestamp.fromDate(date)
    });

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  Future<void> card(WidgetTester tester, FakeFirebaseFirestore db,
      {DateTime Function()? now, VoidCallback? onOpen}) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AdminUpcomingEventCard(
                firestore: db,
                now: now ?? () => start,
                onOpenAgenda: onOpen ?? () {}))));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'earliest future activity shown, updates live, removes cleanly and opens agenda',
      (tester) async {
    final db = FakeFirebaseFirestore();
    var opens = 0;
    await event(db, 'Past', start.subtract(const Duration(days: 1)));
    await event(db, 'Later', start.add(const Duration(days: 3)));
    await event(db, 'Next', DateTime(2026, 11, 5, 18, 30));
    await card(tester, db, onOpen: () => opens++);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Past'), findsNothing);
    expect(find.text('18:30 h'), findsOneWidget);
    expect(find.text('Local de prueba'), findsOneWidget);
    await tester.tap(find.text('Next'));
    expect(opens, 1);
    await db
        .doc('events/Next')
        .update({'title': 'Renamed', 'location': 'Updated location'});
    await tester.pumpAndSettle();
    expect(find.text('Renamed'), findsOneWidget);
    expect(find.text('Updated location'), findsOneWidget);
    await db.doc('events/Next').delete();
    await tester.pumpAndSettle();
    expect(find.text('Later'), findsOneWidget);
    await db.doc('events/Later').delete();
    await tester.pumpAndSettle();
    expect(find.text('No hay reuniones próximas'), findsOneWidget);
  });
  testWidgets(
      'expired activity automatically yields the next without changing database',
      (tester) async {
    final db = FakeFirebaseFirestore();
    var now = start;
    await event(db, 'First', start.add(const Duration(seconds: 10)));
    await event(db, 'Second', start.add(const Duration(hours: 1)));
    await card(tester, db, now: () => now);
    final before = db.dump();
    now = start.add(const Duration(seconds: 11));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('First'), findsNothing);
    expect(db.dump(), before);
  });
  testWidgets('empty agenda is actionable and new activity appears live',
      (tester) async {
    final db = FakeFirebaseFirestore();
    var opens = 0;
    await card(tester, db, onOpen: () => opens++);
    expect(find.text('No hay reuniones próximas'), findsOneWidget);
    await tester.tap(find.text('No hay reuniones próximas'));
    expect(opens, 1);
    await event(db, 'New activity', start.add(const Duration(hours: 1)),
        location: '');
    await tester.pumpAndSettle();
    expect(find.text('New activity'), findsOneWidget);
    expect(find.byIcon(Icons.location_on_outlined), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('agenda read error has explicit fallback and still opens agenda',
      (tester) async {
    final db = UnavailableAgenda();
    var opens = 0;
    await card(tester, db, onOpen: () => opens++);
    expect(find.text('No se pudo consultar la agenda'), findsOneWidget);
    expect(find.text('No hay reuniones próximas'), findsNothing);
    await tester.tap(find.text('No se pudo consultar la agenda'));
    expect(opens, 1);
  });

  for (final width in [320.0, 360.0, 440.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('long meeting text and accessibility fit $width/$scale',
          (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = FakeFirebaseFirestore();
        await event(db, 'long', start.add(const Duration(hours: 2)),
            title: 'Asamblea con un título muy largo ${'x' * 180}',
            location: 'Ubicación extensa ${'y' * 180}');
        await tester.pumpWidget(MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: Scaffold(
                body: AdminDashboardScreen(
                    user: adminUser('Marina de prueba'),
                    firestore: db,
                    now: () => start,
                    onNavigate: (_) {}))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
            find.text('Proyectos comunitarios'), 180,
            scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets('counter filters and all existing destinations are preserved',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = FakeFirebaseFirestore();
    final destinations = <int>[];
    await db.doc('accessRequests/a').set({'status': 'pendiente'});
    await db.doc('accessRequests/b').set({'status': 'rechazado'});
    await db.doc('projects/a').set({'isTrashed': false});
    await db.doc('projects/b').set({'isTrashed': true});
    await db.doc('reports/a').set({'moderationStatus': 'aprobado'});
    await db.doc('reports/b').set({'moderationStatus': 'rechazado'});
    await event(db, 'Past', start.subtract(const Duration(days: 1)));
    await event(db, 'Next', start.add(const Duration(hours: 1)));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AdminDashboardScreen(
                user: adminUser('Marina'),
                firestore: db,
                now: () => start,
                onNavigate: destinations.add))));
    await tester.pumpAndSettle();
    final before = db.dump();
    for (final pair in {
      'Solicitudes': '1',
      'Proyectos': '2',
      'Reportes': '1',
      'Actividades': '2'
    }.entries) {
      final label = find.text(pair.key);
      final tile = find.ancestor(of: label, matching: find.byType(Card)).first;
      expect(find.descendant(of: tile, matching: find.text(pair.value)),
          findsOneWidget);
      await tester.tap(label);
    }
    for (final label in [
      'Next',
      'Solicitudes y vecinos',
      'Agenda comunitaria',
      'Proyectos comunitarios'
    ]) {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
    }
    expect(destinations, [3, 1, 2, 5, 5, 3, 5, 1]);
    expect(db.dump(), before);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'render actual phone layout with fictional data for visual inspection',
      (tester) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = FakeFirebaseFirestore();
    for (var i = 0; i < 8; i++) {
      await db.doc('projects/p$i').set({'isTrashed': false});
    }
    for (var i = 0; i < 7; i++) {
      await db.doc('reports/r$i').set({'moderationStatus': 'aprobado'});
    }
    await event(db, 'Asamblea vecinal', DateTime(2026, 11, 12, 18, 30),
        location: 'Local comunal');
    await event(db, 'Otra actividad', DateTime(2026, 12, 12, 10));
    await tester.runAsync(() async {
      for (final family in [
        'Roboto',
        'Inter_regular',
        'Inter_400',
        'Inter_500',
        'Inter_600',
        'Inter_700',
        'Montserrat_regular',
        'Montserrat_400',
        'Montserrat_500',
        'Montserrat_600',
        'Montserrat_700'
      ]) {
        final bytes = await File(
                'C:/src/flutter/bin/cache/artifacts/material_fonts/roboto-regular.ttf')
            .readAsBytes();
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
      }
      final icons = await File(
              'C:/src/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf')
          .readAsBytes();
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(ByteData.sublistView(icons))))
          .load();
    });
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: RepaintBoundary(
            key: key,
            child: Scaffold(
                appBar: AppBar(
                    title: const Text('MiComunidad'),
                    leading: const Icon(Icons.location_city)),
                body: AdminDashboardScreen(
                    user: adminUser('Marina'),
                    firestore: db,
                    now: () => start,
                    onNavigate: (_) {}),
                bottomNavigationBar: NavigationBar(destinations: const [
                  NavigationDestination(
                      icon: Icon(Icons.dashboard), label: 'Panel'),
                  NavigationDestination(
                      icon: Icon(Icons.construction), label: 'Proyectos'),
                  NavigationDestination(
                      icon: Icon(Icons.report_outlined), label: 'Reportes'),
                  NavigationDestination(
                      icon: Icon(Icons.people_outline), label: 'Vecinos'),
                  NavigationDestination(
                      icon: Icon(Icons.map_outlined), label: 'Mapa'),
                  NavigationDestination(
                      icon: Icon(Icons.event_outlined), label: 'Agenda'),
                ])))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file =
          File('../auditoria-inicio-admin-20261104/admin-dashboard.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    });
    await tester.pumpWidget(const SizedBox());
  });
}
