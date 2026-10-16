import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/models/user_model.dart';
import 'package:micomunidad/screens/admin/admin_dashboard_screen.dart';

AppUser adminUser(String name) => AppUser(
      userId: 'admin-demo',
      email: 'admin@example.com',
      nombre: name,
      role: UserRole.admin,
      approvalStatus: 'aprobado',
      joinDate: DateTime(2026, 1, 1),
      communityId: 'community-demo',
      createdAt: DateTime(2026, 1, 1),
    );

void useLargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> showDashboard(
  WidgetTester tester, {
  required String name,
  ValueChanged<int>? onNavigate,
}) async {
  useLargeViewport(tester);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AdminDashboardScreen(
        user: adminUser(name),
        firestore: FakeFirebaseFirestore(),
        onNavigate: onNavigate ?? (_) {},
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('greets administrator by first name and preserves panel content',
      (tester) async {
    final destinations = <int>[];
    await showDashboard(tester,
        name: 'Marina Salas', onNavigate: destinations.add);

    expect(find.text('Hola, Marina'), findsOneWidget);
    expect(find.text('Hola, Marina Salas'), findsNothing);
    expect(find.text('Panel de control'), findsNothing);
    expect(
      find.text('Gestiona la actividad de la comunidad desde un solo lugar.'),
      findsOneWidget,
    );
    expect(find.text('Conoce más sobre la comunidad'), findsOneWidget);
    expect(find.text('Accesos de administración'), findsOneWidget);
    expect(find.text('Solicitudes'), findsOneWidget);
    expect(find.text('Proyectos'), findsNWidgets(2));
    expect(find.text('Reportes'), findsOneWidget);
    expect(find.text('Actividades'), findsOneWidget);

    await tester.tap(find.text('Solicitudes'));
    await tester.tap(find.text('Proyectos').first);
    await tester.tap(find.text('Reportes'));
    await tester.tap(find.text('Actividades'));
    expect(destinations, [3, 1, 2, 5]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refreshes greeting when the existing profile stream changes',
      (tester) async {
    useLargeViewport(tester);
    final db = FakeFirebaseFirestore();
    final profile = db.collection('users').doc('admin-demo');
    await profile.set(adminUser('Marina Salas').toJson());

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: profile.snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SizedBox.shrink();
            }
            return AdminDashboardScreen(
              user: AppUser.fromFirestore(snapshot.data!),
              firestore: db,
              onNavigate: (_) {},
            );
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Hola, Marina'), findsOneWidget);
    final originalElement = tester.element(find.byType(AdminDashboardScreen));

    await profile.update({'nombre': 'Lucía Torres'});
    await tester.pumpAndSettle();

    expect(find.text('Hola, Lucía'), findsOneWidget);
    expect(find.text('Hola, Marina'), findsNothing);
    expect(tester.element(find.byType(AdminDashboardScreen)),
        same(originalElement));
    expect(
      find.text('Gestiona la actividad de la comunidad desde un solo lugar.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('trims surrounding spaces and ignores repeated whitespace',
      (tester) async {
    await showDashboard(tester, name: '  Álex \t  Rojas  ');
    expect(find.text('Hola, Álex'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final name in ['', '   \t  ']) {
    testWidgets(
        'uses a neutral greeting for ${name.isEmpty ? 'empty' : 'blank'} name',
        (tester) async {
      await showDashboard(tester, name: name);
      expect(find.text('Hola'), findsOneWidget);
      expect(find.text('Hola, '), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
