import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:micomunidad/core/theme/app_theme.dart';
import 'package:micomunidad/models/user_model.dart';
import 'package:micomunidad/screens/neighbor/neighbor_dashboard_screen.dart';

final now = DateTime(2026, 11, 4, 10);
AppUser resident(String name) => AppUser(
    userId: 'resident-test',
    nombre: name,
    email: 'resident@example.com',
    role: UserRole.vecino,
    approvalStatus: 'aprobado',
    joinDate: now,
    communityId: 'fictional',
    createdAt: now);

Future<void> addMeeting(FakeFirebaseFirestore db,
        {String title = 'Asamblea vecinal',
        String location = 'Local comunal'}) =>
    db.doc('events/upcoming').set({
      'title': title,
      'location': location,
      'eventDate': Timestamp.fromDate(DateTime(2026, 11, 12, 18, 30))
    });

Widget dashboard(FakeFirebaseFirestore db,
        {String name = 'Pablo', ValueChanged<int>? onNavigate}) =>
    NeighborDashboardScreen(
        user: resident(name),
        firestore: db,
        now: () => now,
        onNavigate: onNavigate ?? (_) {});

void viewport(WidgetTester tester, double width, [double height = 956]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async => tester.pumpWidget(const SizedBox()));
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('upcoming agenda and quick actions keep resident destinations',
      (tester) async {
    viewport(tester, 440, 1800);
    final db = FakeFirebaseFirestore();
    await addMeeting(db);
    final destinations = <int>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: dashboard(db, onNavigate: destinations.add))));
    await tester.pumpAndSettle();
    expect(find.text('Hola, Pablo'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('NOV'), findsOneWidget);
    expect(find.text('18:30 h'), findsOneWidget);
    for (final label in [
      'Asamblea vecinal',
      'Ver mapa',
      'Proyectos',
      'Nuevo reporte',
      'Agenda'
    ]) {
      await tester.tap(find.text(label));
    }
    expect(destinations, [4, 1, 2, 3, 4]);
    expect(find.text('Actividad comunitaria'), findsOneWidget);
    expect(find.text('Tu participación cuenta'), findsOneWidget);
    expect(
        find.text(
            'Comenta proyectos, comparte fotos y reporta necesidades de la comunidad.'),
        findsOneWidget);
    expect(find.text('Accesos de administración'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty agenda remains actionable and updates with live changes',
      (tester) async {
    viewport(tester, 440);
    final db = FakeFirebaseFirestore();
    final destinations = <int>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: dashboard(db, onNavigate: destinations.add))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No hay reuniones próximas'));
    expect(destinations, [4]);
    await addMeeting(db);
    await tester.pumpAndSettle();
    expect(find.text('Asamblea vecinal'), findsOneWidget);
    await db.doc('events/upcoming').delete();
    await tester.pumpAndSettle();
    expect(find.text('No hay reuniones próximas'), findsOneWidget);
  });

  testWidgets('greeting follows updated profile supplied by home screen',
      (tester) async {
    viewport(tester, 440);
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: dashboard(db, name: 'Pablo Apellido'))));
    await tester.pumpAndSettle();
    expect(find.text('Hola, Pablo'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: dashboard(db, name: 'Marina Apellido'))));
    await tester.pumpAndSettle();
    expect(find.text('Hola, Marina'), findsOneWidget);
    expect(find.text('Hola, Pablo'), findsNothing);
  });

  for (final width in [320.0, 360.0, 440.0, 660.0, 900.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('actions and preserved activity fit $width/$scale',
          (tester) async {
        viewport(tester, width, 2400);
        final db = FakeFirebaseFirestore();
        await addMeeting(db,
            title: List.filled(25, 'Reunión').join(' '),
            location: List.filled(25, 'Ubicación').join(' '));
        await tester.pumpWidget(MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: Scaffold(body: dashboard(db))));
        await tester.pumpAndSettle();
        final heights = <double>[];
        for (final label in [
          'Ver mapa',
          'Proyectos',
          'Nuevo reporte',
          'Agenda'
        ]) {
          final text = find.text(label);
          await tester.scrollUntilVisible(text, 200,
              scrollable: find.byType(Scrollable).first);
          await tester.pumpAndSettle();
          final card =
              find.ancestor(of: text, matching: find.byType(Card)).first;
          final cardRect = tester.getRect(card);
          final textRect = tester.getRect(text);
          expect(cardRect.inflate(.1).contains(textRect.topLeft), true);
          expect(cardRect.inflate(.1).contains(textRect.bottomRight), true);
          heights.add(cardRect.height);
          expect(tester.takeException(), isNull);
        }
        expect(heights[0], heights[1]);
        expect(heights[2], heights[3]);
        await tester.scrollUntilVisible(
            find.text('Tu participación cuenta'), 200,
            scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        expect(find.text('Actividad comunitaria'), findsOneWidget);
        expect(find.byIcon(Icons.groups), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('render resident phone design using fictional data',
      (tester) async {
    viewport(tester, 440);
    final db = FakeFirebaseFirestore();
    await addMeeting(db);
    await tester.runAsync(() async {
      var sdk = File(Platform.resolvedExecutable).parent;
      while (!Directory('${sdk.path}/bin/cache/artifacts/material_fonts')
          .existsSync()) {
        if (sdk.parent.path == sdk.path) {
          throw StateError('Flutter SDK fonts unavailable for visual check');
        }
        sdk = sdk.parent;
      }
      final fonts = '${sdk.path}/bin/cache/artifacts/material_fonts';
      final bytes = await File('$fonts/roboto-regular.ttf').readAsBytes();
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
        await (FontLoader(family)
              ..addFont(Future.value(ByteData.sublistView(bytes))))
            .load();
      }
      final icons =
          await File('$fonts/materialicons-regular.otf').readAsBytes();
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
                    leading: const Icon(Icons.location_city),
                    title: const Text('MiComunidad')),
                body: dashboard(db),
                bottomNavigationBar: NavigationBar(destinations: const [
                  NavigationDestination(
                      icon: Icon(Icons.home), label: 'Inicio'),
                  NavigationDestination(icon: Icon(Icons.map), label: 'Mapa'),
                  NavigationDestination(
                      icon: Icon(Icons.construction), label: 'Proyectos'),
                  NavigationDestination(
                      icon: Icon(Icons.report_outlined), label: 'Reportes'),
                  NavigationDestination(
                      icon: Icon(Icons.event), label: 'Agenda'),
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
          File('../auditoria-inicio-vecino-20261104/neighbor-dashboard.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    });
  });
}
