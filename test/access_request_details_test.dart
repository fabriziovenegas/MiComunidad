import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/models/access_request.dart';
import 'package:micomunidad/widgets/access_request_details.dart';

AccessRequest sample({
  String status = 'rechazado',
  String name = 'Mariana Rojas',
  String email = 'mariana@example.com',
  String address = 'Sector 2, lote 14',
  String reason = 'Quiero participar en las actividades de mi comunidad.',
  String? rejectionReason = 'El documento adjunto no es legible.',
}) =>
    AccessRequest(
      id: 'fictional-request',
      applicantUid: 'fictional-applicant',
      name: name,
      dni: '00000001',
      phone: '900000001',
      email: email,
      address: address,
      timeLivingHere: '5 a 10 años',
      reason: reason,
      identityDocumentUrl:
          'gs://fictional-bucket/access_requests/demo/identity/a.pdf',
      status: status,
      createdAt: DateTime(2026, 10, 28),
      rejectionReason: rejectionReason,
    );

Future<void> open(WidgetTester tester, AccessRequest request,
    {Size size = const Size(414, 896), double textScale = 1}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(useMaterial3: true),
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!),
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => DraggableScrollableSheet(
                    expand: false,
                    initialChildSize: .8,
                    maxChildSize: .95,
                    builder: (_, controller) => ListView(
                      controller: controller,
                      padding: const EdgeInsets.all(20),
                      children: [AccessRequestDetails(request: request)],
                    ),
                  )),
          child: const Text('Abrir solicitud'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Abrir solicitud'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('all original personal and community details remain available',
      (tester) async {
    final request = sample();
    await open(tester, request);
    for (final text in [
      request.name,
      request.dni,
      request.phone,
      request.email,
      request.address,
      request.timeLivingHere,
      request.reason,
      request.rejectionReason!,
      'Datos personales',
      'Datos de la comunidad',
      'Enviada el 28/10/2026',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.text('MR'), findsOneWidget);
    expect(find.text(request.identityDocumentUrl), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final entry in {
    'pendiente': 'Pendiente',
    'aprobado': 'Aprobada',
    'rechazado': 'Rechazada',
    'retirado': 'Acceso retirado',
  }.entries) {
    testWidgets('status ${entry.key} preserves its meaning and internal reason',
        (tester) async {
      await open(tester, sample(status: entry.key));
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('Motivo del rechazo'),
          entry.key == 'rechazado' ? findsOneWidget : findsNothing);
      expect(find.text('El documento adjunto no es legible.'),
          entry.key == 'rechazado' ? findsOneWidget : findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'historical rejection without reason retains the existing fallback',
      (tester) async {
    await open(tester, sample(rejectionReason: null));
    expect(find.text('No se indicó un motivo de rechazo.'), findsOneWidget);
  });

  for (final size in [const Size(320, 640), const Size(414, 896)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('long fields remain readable at $size and text scale $scale',
          (tester) async {
        final request = sample(
          name: ('Mariana Rojas Fernández de la Cruz ' * 3),
          email: '${('correo' * 18)}@example.com',
          address: ('Dirección ficticia con referencias extensas. ' * 5),
          rejectionReason: ('Explicación interna extensa sin recortar. ' * 8),
          reason: ('Motivo de ingreso extenso que debe poder leerse. ' * 10),
        );
        await open(tester, request, size: size, textScale: scale);
        expect(tester.takeException(), isNull);
        for (final value in [
          request.rejectionReason!.trim(),
          request.email,
          request.reason
        ]) {
          await tester.scrollUntilVisible(find.text(value), 180,
              scrollable: find.byType(Scrollable).last, maxScrolls: 100);
          expect(tester.takeException(), isNull);
          final text = tester.widget<Text>(find.text(value));
          expect(text.maxLines, isNull);
          expect(text.overflow, isNot(TextOverflow.ellipsis));
        }
        final position = tester
            .state<ScrollableState>(find.byType(Scrollable).last)
            .position;
        expect(position.maxScrollExtent, greaterThan(0));
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(tester.getBottomLeft(find.text(request.reason)).dy,
            lessThanOrEqualTo(size.height));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'rebuilding with an updated request does not retain stale details',
      (tester) async {
    final current = ValueNotifier(sample(status: 'pendiente'));
    addTearDown(current.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ValueListenableBuilder<AccessRequest>(
              valueListenable: current,
              builder: (_, request, __) =>
                  AccessRequestDetails(request: request)),
        ),
      ),
    ));
    expect(find.text('Pendiente'), findsOneWidget);
    current.value = sample(
        name: 'Nombre actualizado',
        rejectionReason: 'Motivo interno actualizado.');
    await tester.pump();
    expect(find.text('Rechazada'), findsOneWidget);
    expect(find.text('Pendiente'), findsNothing);
    expect(find.text('Nombre actualizado'), findsOneWidget);
    expect(find.text('Motivo interno actualizado.'), findsOneWidget);
    expect(find.text('Mariana Rojas'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final name in ['', '   ', 'Á', '👩🏽‍🔧 Ana']) {
    testWidgets('short, empty and Unicode names do not break the header: $name',
        (tester) async {
      await open(tester, sample(name: name));
      expect(find.text(name), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
