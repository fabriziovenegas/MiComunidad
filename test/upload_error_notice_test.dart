import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/services/file_service.dart';
import 'package:micomunidad/widgets/upload_error_notice.dart';
import 'package:micomunidad/widgets/upload_picker.dart';

const noticeKey = ValueKey('upload-error-notice');
const imageError = 'La imagen no puede superar 10 MB.';
const documentError = 'El archivo no puede superar 5 MB.';

void main() {
  testWidgets('red top notice dismisses automatically after five seconds',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
        onPressed: () => showUploadError(context, imageError),
        child: const Text('Show'),
      ),
    ))));
    await tester.tap(find.text('Show'));
    await tester.pump();
    final notice = find.byKey(noticeKey);
    expect(tester.widget<Material>(notice).color, const Color(0xFFB3261E));
    expect(tester.getTopLeft(notice).dy, lessThan(50));
    expect(find.text(imageError), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    expect(notice, findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(notice, findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final sheet in [true, false]) {
    for (final document in [true, false]) {
      testWidgets(
          'notice is above ${sheet ? 'expanded sheet' : 'dialog'} for ${document ? '5 MB documents' : '10 MB photos'}',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              Widget content(BuildContext modalContext) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const TextField(
                          decoration: InputDecoration(labelText: 'Draft')),
                      TextButton(
                        onPressed: () =>
                            pickUploadWithFeedback(modalContext, () async {
                          throw FileUploadException(
                              document ? documentError : imageError);
                        }),
                        child: const Text('Select'),
                      ),
                    ],
                  );
              if (sheet) {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (modalContext) => DraggableScrollableSheet(
                    expand: false,
                    initialChildSize: .96,
                    maxChildSize: .98,
                    builder: (_, controller) => ListView(
                        controller: controller,
                        children: [content(modalContext)]),
                  ),
                );
              } else {
                showDialog<void>(
                    context: context,
                    builder: (modalContext) =>
                        AlertDialog(content: content(modalContext)));
              }
            },
            child: const Text('Open'),
          ),
        ))));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Preserved draft');
        await tester.tap(find.text('Select'));
        await tester.pumpAndSettle();
        expect(
            find.text(document ? documentError : imageError), findsOneWidget);
        // Hittable X proves the modal/barrier is not hiding the root overlay.
        expect(find.byTooltip('Cerrar aviso').hitTestable(), findsOneWidget);
        expect(tester.getTopLeft(find.byKey(noticeKey)).dy, lessThan(50));
        await tester.tap(find.byTooltip('Cerrar aviso'));
        await tester.pump();
        expect(find.byKey(noticeKey), findsNothing);
        expect(find.text('Preserved draft'), findsOneWidget);
        expect(find.text('Select'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('repeated errors replace the notice and restart its lifetime',
      (tester) async {
    late BuildContext target;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      target = context;
      return const Scaffold();
    })));
    showUploadError(target, imageError);
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    showUploadError(target, documentError);
    await tester.pump();
    expect(find.byKey(noticeKey), findsOneWidget);
    expect(find.text(imageError), findsNothing);
    expect(find.text(documentError), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(noticeKey), findsOneWidget);
    dismissUploadError();
    dismissUploadError();
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    expect(find.byKey(noticeKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'disposing the app cancels the notice timer and permits another app',
      (tester) async {
    late BuildContext target;
    Widget app() => MaterialApp(home: Builder(builder: (context) {
          target = context;
          return const Scaffold();
        }));
    await tester.pumpWidget(app());
    showUploadError(target, imageError);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(app());
    showUploadError(target, documentError);
    await tester.pump();
    expect(find.text(documentError), findsOneWidget);
    await tester.tap(find.byTooltip('Cerrar aviso'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('root notice is above a dialog in a nested navigator',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                      body: TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      useRootNavigator: false,
                      builder: (dialogContext) => AlertDialog(actions: [
                        TextButton(
                          onPressed: () =>
                              showUploadError(dialogContext, imageError),
                          child: const Text('Show'),
                        )
                      ]),
                    ),
                    child: const Text('Open'),
                  )),
                ))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show'));
    await tester.pump();
    expect(find.byTooltip('Cerrar aviso').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('Cerrar aviso'));
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'notice respects safe area and large text with keyboard on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late BuildContext target;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            padding: EdgeInsets.only(top: 44),
            viewPadding: EdgeInsets.only(top: 44),
            viewInsets: EdgeInsets.only(bottom: 260),
            textScaler: TextScaler.linear(2),
          ),
          child: child!),
      home: Builder(builder: (context) {
        target = context;
        return const Scaffold();
      }),
    ));
    showUploadError(target, imageError);
    await tester.pump();
    final bounds = tester.getRect(find.byKey(noticeKey));
    expect(bounds.top, greaterThanOrEqualTo(44));
    expect(bounds.left, greaterThanOrEqualTo(16));
    expect(bounds.right, lessThanOrEqualTo(304));
    expect(bounds.bottom, lessThan(380));
    expect(find.byTooltip('Cerrar aviso').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('Cerrar aviso'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('accessible navigation keeps error until manually dismissed',
      (tester) async {
    late BuildContext target;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(accessibleNavigation: true),
          child: child!),
      home: Builder(builder: (context) {
        target = context;
        return const Scaffold();
      }),
    ));
    showUploadError(target, documentError);
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    expect(find.text(documentError), findsOneWidget);
    await tester.tap(find.byTooltip('Cerrar aviso'));
    await tester.pump();
    expect(find.byKey(noticeKey), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
