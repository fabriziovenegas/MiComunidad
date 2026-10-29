import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/models/user_model.dart';
import 'package:micomunidad/widgets/member_details_sheet.dart';

AppUser sample(
        {String id = 'fictional-member',
        UserRole role = UserRole.vecino,
        String status = 'aprobado',
        String name = 'Daniel Rojas'}) =>
    AppUser(
        userId: id,
        email: 'daniel@example.com',
        nombre: name,
        role: role,
        approvalStatus: status,
        joinDate: DateTime(2026, 10, 29),
        createdAt: DateTime(2026, 10, 29),
        communityId: 'fictional-community',
        dni: '00000001',
        phone: '900000001',
        address: 'Sector 2, lote 14',
        timeLivingHere: '5 a 10 años',
        reason: 'Quiero participar en las actividades de mi comunidad.');

Future<void> open(WidgetTester tester,
    {required Stream<List<AppUser>> members,
    AppUser? viewer,
    String memberId = 'fictional-member',
    Size size = const Size(414, 896),
    double scale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(useMaterial3: true),
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: Scaffold(
        body: Builder(
            builder: (context) => ListTile(
                  title: const Text('Abrir ficha'),
                  onTap: () => showMemberDetailsSheet(context,
                      viewer: viewer ??
                          sample(id: 'fictional-admin', role: UserRole.admin),
                      memberId: memberId,
                      members: members),
                ))),
  ));
  await tester.tap(find.text('Abrir ficha'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets(
      'member detail displays all current profile fields and no request data',
      (tester) async {
    final member = sample();
    await open(tester, members: Stream.value([member]));
    for (final value in [
      member.nombre,
      member.dni,
      member.phone!,
      member.email,
      member.address,
      member.timeLivingHere,
      member.reason,
      'Información del miembro',
      'Datos actuales del perfil',
      'Vecino'
    ]) {
      expect(find.text(value), findsOneWidget);
    }
    expect(find.text('DR'), findsOneWidget);
    for (final label in [
      'Motivo del rechazo',
      'Aprobada',
      'Rechazada',
      'Abrir documento adjunto',
      'Guardar cambios',
      'Editar perfil'
    ]) {
      expect(find.text(label), findsNothing);
    }
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('own administrator card opens the same read-only current profile',
      (tester) async {
    final own = sample(id: 'fictional-admin', role: UserRole.admin);
    await open(tester,
        members: Stream.value([own]), viewer: own, memberId: own.userId);
    expect(find.text(own.nombre), findsOneWidget);
    expect(find.text('Administrador'), findsOneWidget);
    expect(find.text('Guardar cambios'), findsNothing);
  });

  testWidgets(
      'profile corrections and role changes update the open sheet by UID',
      (tester) async {
    final controller = StreamController<List<AppUser>>.broadcast();
    addTearDown(controller.close);
    await open(tester, members: controller.stream);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final member = sample();
    controller.add([member]);
    await tester.pumpAndSettle();
    expect(find.text(member.dni), findsOneWidget);
    final updated = member.copyWith(
        nombre: 'Nombre actualizado',
        dni: '00000002',
        phone: '900000002',
        email: 'updated@example.com',
        address: 'Dirección actual',
        timeLivingHere: 'Más de 10 años',
        reason: 'Motivo actual',
        role: UserRole.admin);
    controller
        .add([sample(id: 'another-member', name: 'Another person'), updated]);
    await tester.pumpAndSettle();
    for (final value in [
      updated.nombre,
      updated.dni,
      updated.phone!,
      updated.email,
      updated.address,
      updated.timeLivingHere,
      updated.reason,
      'Administrador'
    ]) {
      expect(find.text(value), findsOneWidget);
    }
    for (final value in [
      member.nombre,
      member.dni,
      member.email,
      member.reason,
      'Another person',
      'Vecino'
    ]) {
      expect(find.text(value), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'removing access hides the previous profile instead of keeping a snapshot',
      (tester) async {
    final controller = StreamController<List<AppUser>>.broadcast();
    addTearDown(controller.close);
    await open(tester, members: controller.stream);
    controller.add([sample()]);
    await tester.pumpAndSettle();
    controller.add([sample(id: 'different-member')]);
    await tester.pumpAndSettle();
    expect(find.text('Este miembro ya no está disponible.'), findsOneWidget);
    expect(find.byType(MemberProfileDetails), findsNothing);
    controller.add([sample(status: 'retirado')]);
    await tester.pumpAndSettle();
    expect(find.byType(MemberProfileDetails), findsNothing);
  });

  testWidgets(
      'read errors hide personal data and a later valid result can recover',
      (tester) async {
    final controller = StreamController<List<AppUser>>.broadcast();
    addTearDown(controller.close);
    await open(tester, members: controller.stream);
    controller.add([sample()]);
    await tester.pumpAndSettle();
    controller.addError(StateError('Fictional permission error'));
    await tester.pumpAndSettle();
    expect(find.text('No se pudo cargar la información del miembro.'),
        findsOneWidget);
    expect(find.text(sample().dni), findsNothing);
    expect(find.byType(MemberProfileDetails), findsNothing);
    controller.add([sample()]);
    await tester.pumpAndSettle();
    expect(find.text(sample().dni), findsOneWidget);
  });

  for (final viewer in [
    sample(role: UserRole.vecino),
    sample(role: UserRole.admin, status: 'pendiente'),
    sample(role: UserRole.admin, status: 'retirado')
  ]) {
    testWidgets(
        'viewer ${viewer.role}/${viewer.approvalStatus} cannot open or subscribe',
        (tester) async {
      final controller = StreamController<List<AppUser>>.broadcast();
      addTearDown(controller.close);
      await open(tester, members: controller.stream, viewer: viewer);
      expect(controller.hasListener, isFalse);
      expect(find.byType(MemberDetailsSheet), findsNothing);
    });
  }

  testWidgets('legacy empty profile fields have a neutral placeholder',
      (tester) async {
    final member = AppUser(
        userId: 'fictional-member',
        email: 'legacy@example.com',
        nombre: 'Legacy profile',
        role: UserRole.admin,
        approvalStatus: 'aprobado',
        joinDate: DateTime(2026),
        createdAt: DateTime(2026),
        communityId: 'fictional');
    await open(tester, members: Stream.value([member]));
    expect(find.text('No indicado'), findsNWidgets(5));
    expect(find.text('Administrador'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final role in UserRole.values) {
    for (final width in [320.0, 414.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('long profile $role fits width $width text scale $scale',
            (tester) async {
          final member = sample(
                  role: role, name: 'Nombre y apellidos largos ' * 5)
              .copyWith(
                  email: '${'correo' * 20}@example.com',
                  address: 'Dirección extensa para comprobar el ajuste. ' * 6,
                  reason: 'Motivo de ingreso largo que debe leerse completo. ' *
                      12);
          await open(tester,
              members: Stream.value([member]),
              size: Size(width, 896),
              scale: scale);
          expect(tester.takeException(), isNull);
          expect(
              tester
                  .widget<Text>(
                      find.byKey(const ValueKey('member-profile-name')))
                  .maxLines,
              isNull);
          for (final value in [member.email, member.address, member.reason]) {
            await tester.scrollUntilVisible(find.text(value), 180,
                scrollable: find.byType(Scrollable).last, maxScrolls: 100);
            expect(tester.widget<Text>(find.text(value)).overflow,
                isNot(TextOverflow.ellipsis));
            expect(tester.takeException(), isNull);
          }
          final scroll = tester
              .state<ScrollableState>(find.byType(Scrollable).last)
              .position;
          scroll.jumpTo(scroll.maxScrollExtent);
          await tester.pumpAndSettle();
          expect(tester.getBottomLeft(find.text(member.reason)).dy,
              lessThanOrEqualTo(896));
        });
      }
    }
  }

  for (final role in UserRole.values) {
    testWidgets('$role badge remains next to the name when there is room',
        (tester) async {
      await open(tester,
          members: Stream.value([sample(role: role)]),
          size: const Size(900, 1800));
      final name =
          tester.getRect(find.byKey(const ValueKey('member-profile-name')));
      final badge =
          tester.getRect(find.byKey(const ValueKey('member-profile-role')));
      expect(badge.left, greaterThanOrEqualTo(name.right));
      expect(badge.top, closeTo(name.top, .01));
      expect(tester.takeException(), isNull);
    });
  }
}
