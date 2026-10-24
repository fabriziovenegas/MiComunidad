import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/models/user_model.dart';
import 'package:micomunidad/widgets/current_report_author_name.dart';

AppUser viewer(
        {String id = 'viewer-demo',
        String name = 'Viewer Demo',
        UserRole role = UserRole.vecino}) =>
    AppUser(
        userId: id,
        email: 'demo@example.com',
        nombre: name,
        role: role,
        approvalStatus: 'aprobado',
        joinDate: DateTime(2026),
        communityId: 'demo',
        createdAt: DateTime(2026));

Future<void> showName(WidgetTester tester,
        {AppUser? user,
        String reportId = 'report-demo',
        String authorId = 'author-demo',
        String savedName = 'Original Demo Name',
        required Future<String?> Function(String) loader}) =>
    tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CurrentReportAuthorName(
                reportId: reportId,
                authorId: authorId,
                savedName: savedName,
                viewer: user ?? viewer(),
                loadName: loader))));

void main() {
  testWidgets('shows the fallback while loading, then only the current name',
      (tester) async {
    final pending = Completer<String?>();
    final calls = <String>[];
    await showName(tester, loader: (id) {
      calls.add(id);
      return pending.future;
    });
    expect(find.text('Original Demo Name'), findsOneWidget);
    pending.complete('Current Demo Name');
    await tester.pumpAndSettle();
    expect(find.text('Current Demo Name'), findsOneWidget);
    expect(find.text('Original Demo Name'), findsNothing);
    expect(calls, ['report-demo']);
    expect(tester.takeException(), isNull);
  });
  for (final role in UserRole.values) {
    testWidgets(
        '$role own reports use the current profile and refresh without backend calls',
        (tester) async {
      var calls = 0;
      Future<String?> load(String _) async {
        calls++;
        return 'Should not be shown';
      }

      await showName(tester,
          authorId: 'viewer-demo',
          user: viewer(name: 'First Demo Name', role: role),
          loader: load);
      expect(find.text('First Demo Name'), findsOneWidget);
      final originalElement =
          tester.element(find.byType(CurrentReportAuthorName));
      await showName(tester,
          authorId: 'viewer-demo',
          user: viewer(name: 'Updated Demo Name', role: role),
          loader: load);
      await tester.pumpAndSettle();
      expect(find.text('Updated Demo Name'), findsOneWidget);
      expect(find.text('First Demo Name'), findsNothing);
      expect(tester.element(find.byType(CurrentReportAuthorName)),
          same(originalElement));
      expect(calls, 0);
    });
  }
  for (final value in <String?>[null, '', '   ']) {
    testWidgets('missing account/name $value keeps the original name',
        (tester) async {
      await showName(tester, loader: (_) async => value);
      await tester.pumpAndSettle();
      expect(find.text('Original Demo Name'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'offline or permission error preserves the saved name without breaking the screen',
      (tester) async {
    await showName(tester,
        loader: (_) async =>
            throw StateError('Private details must not appear'));
    await tester.pumpAndSettle();
    expect(find.text('Original Demo Name'), findsOneWidget);
    expect(find.textContaining('Private details'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('missing original name falls back to Vecino', (tester) async {
    await showName(tester, savedName: ' ', loader: (_) async => null);
    await tester.pumpAndSettle();
    expect(find.text('Vecino'), findsOneWidget);
  });
  testWidgets(
      'changing report or viewer never displays an old asynchronous result',
      (tester) async {
    final first = Completer<String?>();
    final second = Completer<String?>();
    Future<String?> load(String id) =>
        id == 'report-demo' ? first.future : second.future;
    await showName(tester, loader: load);
    await showName(tester,
        reportId: 'another-demo',
        authorId: 'second-author',
        user: viewer(id: 'another-viewer'),
        savedName: 'Second Saved Name',
        loader: load);
    first.complete('First Current Name');
    await tester.pumpAndSettle();
    expect(find.text('First Current Name'), findsNothing);
    expect(find.text('Second Saved Name'), findsOneWidget);
    second.complete('Second Current Name');
    await tester.pumpAndSettle();
    expect(find.text('Second Current Name'), findsOneWidget);
  });
  testWidgets('resuming the app reloads a changed name', (tester) async {
    var name = 'Current Demo Name';
    var calls = 0;
    Future<String?> load(String _) async {
      calls++;
      return name;
    }

    await showName(tester, loader: load);
    await tester.pumpAndSettle();
    expect(find.text('Current Demo Name'), findsOneWidget);
    name = 'Changed Elsewhere';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Changed Elsewhere'), findsOneWidget);
    expect(calls, 2);
  });
  testWidgets('a disposed widget does not reload when the app resumes',
      (tester) async {
    var calls = 0;
    await showName(tester, loader: (_) async {
      calls++;
      return 'Demo Name';
    });
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('a long updated name wraps at 320 pixels and large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: Scaffold(
                body: Row(children: [
              const Icon(Icons.person_outline),
              Expanded(
                  child: CurrentReportAuthorName(
                      reportId: 'demo',
                      authorId: 'demo-author',
                      savedName: 'Demo',
                      loadName: (_) async =>
                          'A long fictional complete name that can occupy more than one line'))
            ])))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
