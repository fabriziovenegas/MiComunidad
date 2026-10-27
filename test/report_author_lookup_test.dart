// Local Functions double only: no deployed function or community data is used.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_functions_platform_interface/cloud_functions_platform_interface.dart'
    as platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/services/community_service.dart';
import 'current_report_author_name_test.dart' show showName;

class LookupFunctions extends platform.FirebaseFunctionsPlatform {
  LookupFunctions() : super(null, 'southamerica-east1');
  Object? error;
  Object? name;
  final calls = <String>[];
  final payloads = <dynamic>[];
  @override
  platform.FirebaseFunctionsPlatform delegateFor(
          {FirebaseApp? app, required String region}) =>
      this;
  @override
  platform.HttpsCallablePlatform httpsCallable(
          String? origin, String name, platform.HttpsCallableOptions options) =>
      LookupCallable(this, origin, name, options);
}

class LookupCallable extends platform.HttpsCallablePlatform {
  LookupCallable(LookupFunctions owner, String? origin, String name,
      platform.HttpsCallableOptions options)
      : super(owner, origin, name, options, null);
  @override
  Future<dynamic> call([dynamic parameters]) async {
    final owner = functions as LookupFunctions;
    owner.calls.add(name!);
    owner.payloads.add(parameters);
    if (owner.error != null) throw owner.error!;
    return <String, dynamic>{'name': owner.name};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  final functions = LookupFunctions();
  setUpAll(() async {
    await Firebase.initializeApp();
    platform.FirebaseFunctionsPlatform.instance = functions;
  });
  setUp(() {
    functions.error = null;
    functions.name = null;
    functions.calls.clear();
    functions.payloads.clear();
  });

  for (final code in [
    'unavailable',
    'deadline-exceeded',
    'network-request-failed'
  ]) {
    test('optional author lookup returns no new name for $code', () async {
      functions.error = FirebaseFunctionsException(
          code: code, message: 'Local test', details: null);
      expect(
          await CommunityService.instance
              .currentReportAuthorName('fictional-report'),
          isNull);
      expect(functions.calls, ['getReportAuthorName']);
    });
  }
  test('an explicit timeout also falls back', () async {
    functions.error = TimeoutException('Fictional timeout');
    expect(
        await CommunityService.instance
            .currentReportAuthorName('fictional-report'),
        isNull);
  });
  test('successful lookup still returns the current trimmed name', () async {
    functions.name = '  Nombre actualizado  ';
    expect(
        await CommunityService.instance
            .currentReportAuthorName('fictional-report'),
        'Nombre actualizado');
  });
  for (final value in [null, '', '   ', 123]) {
    test('missing or invalid name $value does not replace the saved name',
        () async {
      functions.name = value;
      expect(
          await CommunityService.instance
              .currentReportAuthorName('fictional-report'),
          isNull);
    });
  }
  for (final code in ['permission-denied', 'internal']) {
    test('non-network failure $code remains observable to callers', () async {
      functions.error = FirebaseFunctionsException(
          code: code, message: 'Local test', details: null);
      await expectLater(
          CommunityService.instance.currentReportAuthorName('fictional-report'),
          throwsA(isA<FirebaseFunctionsException>()
              .having((e) => e.code, 'code', code)));
    });
  }
  testWidgets('real service offline response keeps saved author in the widget',
      (tester) async {
    functions.error = FirebaseFunctionsException(
        code: 'unavailable', message: 'Local test', details: null);
    await showName(tester,
        loader: CommunityService.instance.currentReportAuthorName);
    await tester.pumpAndSettle();
    expect(find.text('Original Demo Name'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final collection in ['projects', 'events']) {
    test('$collection uses the restricted content-author callable', () async {
      functions.name = 'Nombre actual';
      expect(
          await CommunityService.instance
              .currentContentAuthorName(collection, 'demo-content'),
          'Nombre actual');
      expect(functions.calls, ['getContentAuthorName']);
      expect(functions.payloads, [
        {'collection': collection, 'contentId': 'demo-content'}
      ]);
    });
    test('$collection name lookup falls back when offline', () async {
      functions.error = FirebaseFunctionsException(
          code: 'unavailable', message: 'Local test');
      expect(
          await CommunityService.instance
              .currentContentAuthorName(collection, 'demo-content'),
          isNull);
    });
  }
  test('content lookup cannot be redirected to profiles or other collections',
      () async {
    await expectLater(
        CommunityService.instance.currentContentAuthorName('users', 'demo'),
        throwsArgumentError);
    expect(functions.calls, isEmpty);
  });
}
