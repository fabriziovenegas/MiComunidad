import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/models/access_request.dart';
import 'package:micomunidad/widgets/access_request_preview_card.dart';

AccessRequest sample(String status, {String name = 'Mariana Rojas'}) =>
    AccessRequest(
      id: 'fictional-$status',
      applicantUid: 'fictional-applicant',
      name: name,
      dni: '00000001',
      phone: '900000001',
      email: 'fictional@example.com',
      address: 'Fictional address',
      timeLivingHere: '5 a 10 años',
      reason: 'Fictional application',
      identityDocumentUrl: 'gs://fictional/access_requests/demo/identity/a.pdf',
      rejectionReason: 'Private fictional rejection reason',
      status: status,
      createdAt: DateTime(2026, 10, 28),
    );

Future<void> showCard(WidgetTester tester, AccessRequest request,
    {double textScale = 1,
    double width = 414,
    VoidCallback? onOpen,
    Widget? actions}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 896);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(useMaterial3: true),
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: AccessRequestPreviewCard(
            request: request, onOpen: onOpen ?? () {}, reviewActions: actions),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });
  for (final width in [320.0, 414.0]) {
    for (final scale in [1.0, 1.5, 2.0, 3.0]) {
      testWidgets(
          'all status sizes and columns match at width $width scale $scale',
          (tester) async {
        Size? firstSize;
        double? firstLeft;
        double? firstDateLeft;
        for (final status in [
          'aprobado',
          'rechazado',
          'retirado',
          'pendiente'
        ]) {
          for (final name in [
            'Mariana Rojas',
            'Nombre muy largo con muchos apellidos ' * 5,
            'NombreSinEspacios' * 12,
          ]) {
            await showCard(tester, sample(status, name: name),
                width: width, textScale: scale);
            expect(tester.takeException(), isNull);
            final badge = find.byKey(const ValueKey('request-preview-status'));
            final rect = tester.getRect(badge);
            final dateRect = tester
                .getRect(find.byKey(const ValueKey('request-preview-date')));
            firstSize ??= rect.size;
            firstLeft ??= rect.left;
            firstDateLeft ??= dateRect.left;
            expect(rect.size, firstSize);
            expect(rect.left, closeTo(firstLeft, .01));
            expect(dateRect.left, closeTo(firstDateLeft, .01));
            expect(rect.left, greaterThanOrEqualTo(12));
            expect(rect.right, lessThanOrEqualTo(width - 12));
            final text = tester.widget<Text>(
                find.byKey(const ValueKey('request-preview-name')));
            expect(text.maxLines, 2);
            expect(text.overflow, TextOverflow.ellipsis);
            expect(text.data, name);
            expect(find.text('28/10/2026'), findsOneWidget);
          }
        }
      });
    }
  }

  for (final entry in {
    'aprobado': 'Aprobada',
    'rechazado': 'Rechazada',
    'retirado': 'Acceso retirado',
    'pendiente': 'Pendiente',
  }.entries) {
    testWidgets(
        'status ${entry.key} keeps its meaning and hides private details',
        (tester) async {
      final request = sample(entry.key);
      var opens = 0;
      await showCard(tester, request, onOpen: () => opens++);
      expect(find.text(entry.value), findsOneWidget);
      for (final value in [
        request.rejectionReason!,
        request.dni,
        request.phone,
        request.email,
        request.address,
        request.identityDocumentUrl
      ]) {
        expect(find.text(value), findsNothing);
      }
      await tester.tap(find.text(request.name));
      expect(opens, 1);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });
  }

  testWidgets('pending quick actions stay independent from opening the detail',
      (tester) async {
    var opens = 0;
    var approvals = 0;
    var rejections = 0;
    await showCard(tester, sample('pendiente'),
        width: 320,
        textScale: 2,
        onOpen: () => opens++,
        actions: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                tooltip: 'Rechazar',
                onPressed: () => rejections++,
                icon: const Icon(Icons.close)),
            IconButton(
                tooltip: 'Aprobar',
                onPressed: () => approvals++,
                icon: const Icon(Icons.check_circle)),
          ],
        ));
    await tester.ensureVisible(find.byTooltip('Aprobar'));
    await tester.tap(find.byTooltip('Aprobar'));
    expect(approvals, 1);
    expect(rejections, 0);
    expect(opens, 0);
    await tester.tap(find.byTooltip('Rechazar'));
    expect(rejections, 1);
    expect(opens, 0);
    await tester.ensureVisible(find.text('Mariana Rojas'));
    await tester.tap(find.text('Mariana Rojas'));
    expect(opens, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled review buttons do not submit an operation',
      (tester) async {
    await showCard(tester, sample('pendiente'),
        actions: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                tooltip: 'Rechazar', onPressed: null, icon: Icon(Icons.close)),
            IconButton(
                tooltip: 'Aprobar',
                onPressed: null,
                icon: Icon(Icons.check_circle)),
          ],
        ));
    final buttons = tester.widgetList<IconButton>(find.byType(IconButton));
    expect(buttons, hasLength(2));
    expect(buttons.every((button) => button.onPressed == null), isTrue);
  });

  for (final name in ['', ' ', 'Á', '👩🏽‍🔧 Ana']) {
    testWidgets('avatar and title accept unusual names: $name', (tester) async {
      await showCard(tester, sample('rechazado', name: name), width: 320);
      expect(tester.takeException(), isNull);
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('request-preview-name')))
              .data,
          name);
    });
  }
}
