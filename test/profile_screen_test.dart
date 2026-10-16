import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/models/user_model.dart';
import 'package:micomunidad/screens/profile_screen.dart';

void main() {
  Future<void> prepareView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  final user = AppUser(
    userId: 'demo-resident',
    email: 'resident@example.com',
    nombre: 'Demo Resident',
    role: UserRole.vecino,
    approvalStatus: 'aprobado',
    joinDate: DateTime(2026),
    phone: '000000001',
    dni: '00000001',
    address: 'Demo address',
    timeLivingHere: '1 a 5 años',
    reason: 'Fictional registration',
    communityId: 'community',
    createdAt: DateTime(2026),
  );

  testWidgets(
      'save sends all seven fields once and keeps the form while waiting',
      (tester) async {
    await prepareView(tester);
    final done = Completer<void>();
    final calls = <Map<String, String>>[];
    await tester.pumpWidget(MaterialApp(
      home: ProfileScreen(
        user: user,
        onSave: (
            {required nombre,
            required dni,
            required phone,
            required email,
            required address,
            required timeLivingHere,
            required reason}) {
          calls.add({
            'nombre': nombre,
            'dni': dni,
            'phone': phone,
            'email': email,
            'address': address,
            'timeLivingHere': timeLivingHere,
            'reason': reason
          });
          return done.future;
        },
      ),
    ));
    final inputs = find.byType(TextFormField);
    await tester.enterText(inputs.at(0), 'Updated Demo Resident');
    await tester.enterText(inputs.at(1), '00000002');
    await tester.enterText(inputs.at(2), '000000002');
    await tester.enterText(inputs.at(3), 'updated@example.com');
    await tester.ensureVisible(inputs.at(4));
    await tester.enterText(inputs.at(4), 'Updated demo address');
    await tester.ensureVisible(inputs.at(5));
    await tester.enterText(inputs.at(5), 'Updated fictional reason');
    await tester.ensureVisible(find.text('Guardar cambios'));
    await tester.tap(find.text('Guardar cambios'));
    await tester.pump();
    expect(calls, hasLength(1));
    expect(calls.single, {
      'nombre': 'Updated Demo Resident',
      'dni': '00000002',
      'phone': '000000002',
      'email': 'updated@example.com',
      'address': 'Updated demo address',
      'timeLivingHere': '1 a 5 años',
      'reason': 'Updated fictional reason',
    });
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    done.complete();
    await tester.pumpAndSettle();
    expect(find.text('Cambios guardados correctamente.'), findsOneWidget);
  });

  testWidgets('a rejected DNI correction preserves entries and permits retry',
      (tester) async {
    await prepareView(tester);
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: ProfileScreen(
        user: user,
        onSave: (
            {required nombre,
            required dni,
            required phone,
            required email,
            required address,
            required timeLivingHere,
            required reason}) async {
          calls++;
          throw FirebaseFunctionsException(
              code: 'already-exists',
              message: 'El DNI ya pertenece a otra cuenta.');
        },
      ),
    ));
    await tester.enterText(find.byType(TextFormField).at(1), '00000002');
    await tester.ensureVisible(find.text('Guardar cambios'));
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    expect(find.text('El DNI ya pertenece a otra cuenta.'), findsOneWidget);
    expect(find.text('Cambios guardados correctamente.'), findsNothing);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(1))
            .controller!
            .text,
        '00000002');
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('invalid required community fields prevent save', (tester) async {
    await prepareView(tester);
    var called = false;
    await tester.pumpWidget(MaterialApp(
      home: ProfileScreen(
        user: user,
        onSave: (
            {required nombre,
            required dni,
            required phone,
            required email,
            required address,
            required timeLivingHere,
            required reason}) async {
          called = true;
        },
      ),
    ));
    final address = find.byType(TextFormField).at(4);
    await tester.ensureVisible(address);
    await tester.enterText(address, '');
    await tester.ensureVisible(find.text('Guardar cambios'));
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    expect(called, isFalse);
    expect(find.text('Este campo es obligatorio.'), findsOneWidget);
  });
}
