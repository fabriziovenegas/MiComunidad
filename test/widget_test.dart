import 'package:flutter/material.dart';
import 'package:micomunidad/config/app_identity.dart';
import 'package:micomunidad/config/community_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/config/community_map_data.dart';
import 'package:micomunidad/models/user_model.dart';
import 'package:micomunidad/screens/auth/login_screen.dart';
import 'package:micomunidad/screens/onboarding/welcome_screen.dart';
import 'package:micomunidad/services/community_service.dart';
import 'package:micomunidad/utils/text_encoding.dart';
import 'package:micomunidad/widgets/community_info_dialog.dart';

// All profiles and community counts below are fictional test data.
void main() {
  test('solo existen los roles vecino y administrador', () {
    expect(UserRole.values.map((role) => role.name), ['vecino', 'admin']);
  });

  test('el mapa conserva referencias y usa un solo perímetro comunitario', () {
    expect(CommunityMapData.landmarks, hasLength(8));
    expect(CommunityMapData.communityBoundary.length, greaterThanOrEqualTo(20));
  });

  test('las iniciales son seguras para nombres cortos', () {
    final user = AppUser(
      userId: '1',
      email: 'vecino@example.com',
      nombre: 'Ana',
      role: UserRole.vecino,
      approvalStatus: 'aprobado',
      joinDate: DateTime(2026),
      communityId: 'community',
      createdAt: DateTime(2026),
    );
    expect(user.initials, 'A');
    expect(user.isNeighbor, isTrue);
    expect(user.isAdmin, isFalse);
  });

  test('repara nombres históricos con tildes dañadas', () {
    expect(readableText('Persona MarÃ­a Demo'), 'Persona María Demo');
    expect(readableText('Usuario Guti�rrez Demo'), 'Usuario Gutiérrez Demo');
  });

  testWidgets('el login muestra las acciones principales', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
    expect(find.text('Solicitar ingreso'), findsOneWidget);
  });

  testWidgets('cancelar la recuperación no falla durante el cierre del diálogo',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.enterText(
      find.byType(TextFormField).first,
      'vecino@example.com',
    );
    await tester.ensureVisible(find.text('¿Olvidaste tu contraseña?'));
    await tester.tap(find.text('¿Olvidaste tu contraseña?'));
    await tester.pumpAndSettle();

    final dialogField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextFormField),
    );
    expect(
      tester.widget<TextFormField>(dialogField).initialValue,
      'vecino@example.com',
    );
    await tester.enterText(dialogField, 'otro@example.com');
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.ensureVisible(find.text('¿Olvidaste tu contraseña?'));
    await tester.tap(find.text('¿Olvidaste tu contraseña?'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(dialogField).initialValue,
      'vecino@example.com',
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('la bienvenida coincide con el recorrido de ingreso',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WelcomeScreen(
          summary: Future.value(const PublicCommunitySummary(
            activeMembers: 3,
            projects: 0,
          )),
        ),
        routes: {'/login': (_) => const LoginScreen()},
      ),
    );

    expect(find.text(AppIdentity.appName), findsOneWidget);
    expect(find.text('Bienvenido a ${AppIdentity.shortName}'), findsOneWidget);
    expect(find.text('Sobre ${AppIdentity.appName}'), findsOneWidget);
    expect(
        find.text(
            'Tu plataforma digital para conectar, participar y mejorar nuestro barrio juntos.'),
        findsNothing);
    expect(
        find.text(
            'Es un espacio digital creado para mantener informados a los vecinos, registrar problemáticas, dar seguimiento a proyectos y participar en las actividades de la comunidad.'),
        findsOneWidget);
    expect(
        find.text(
            'Fortalecer la participación vecinal y facilitar la organización de la comunidad, promoviendo un entorno más seguro, ordenado y colaborativo para todos.'),
        findsOneWidget);
    expect(find.text('Comenzar'), findsOneWidget);
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('Sin reunión agendada'), findsNothing);
    expect(find.text('Nuestra Misión'), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) =>
          widget is Container && widget.color == const Color(0xFFC5F3E1)),
      findsNothing,
    );
    final heroImage = find.byType(Image).first;
    expect(tester.widget<Image>(heroImage).fit, BoxFit.cover);
    expect(tester.getSize(heroImage).height, 290);
    expect(
      tester.getTopLeft(find.text('Sobre ${AppIdentity.appName}')).dy -
          tester.getBottomLeft(heroImage).dy,
      closeTo(24, 0.1),
    );
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final content = text.data ?? '';
      if (content == AppIdentity.appName ||
          content == 'Bienvenido a ${AppIdentity.shortName}' ||
          content == 'Sobre ${AppIdentity.appName}' ||
          content == 'Nuestra Misión' ||
          content.startsWith('Es un espacio digital creado') ||
          content.startsWith('Fortalecer la participación vecinal')) {
        expect(text.textAlign, TextAlign.left);
      }
    }
  });

  testWidgets('la información comunitaria muestra su historia e imágenes',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(child: CommunityInfoButton()),
          ),
        ),
      ),
    );

    expect(find.text('Conoce más sobre la comunidad'), findsOneWidget);
    await tester.tap(find.text('Conoce más sobre la comunidad'));
    await tester.pumpAndSettle();

    expect(find.text('Nuestra comunidad'), findsOneWidget);
    expect(
      find.text(CommunityConfig.legalName),
      findsOneWidget,
    );
    expect(find.text('Nuestra historia'), findsOneWidget);
    for (final paragraph in CommunityConfig.history) {
      expect(find.text(paragraph), findsOneWidget);
    }
    expect(find.byType(Image), findsNWidgets(3));

    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();
    expect(find.text('Nuestra comunidad'), findsNothing);
  });
}
