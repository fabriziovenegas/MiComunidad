import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/core/firebase/app_check_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('does not activate before explicit local configuration', () async {
    var invoked = false;
    expect(
        await AppCheckConfig.initialize(
            enabled: false, activate: (_) async => invoked = true),
        isFalse);
    expect(invoked, isFalse);
  });

  test('release never selects the debug provider even with a supplied token',
      () {
    final provider = AppCheckConfig.androidProvider(
        debug: false, debugToken: 'fictional-development-secret');
    expect(provider, isA<AndroidPlayIntegrityProvider>());
    expect(provider, isNot(isA<AndroidDebugProvider>()));
  });

  test('development can use a local token or native automatic generation', () {
    final local = AppCheckConfig.androidProvider(
        debug: true, debugToken: ' fictional-local-token ');
    expect((local as AndroidDebugProvider).debugToken, 'fictional-local-token');
    final automatic =
        AppCheckConfig.androidProvider(debug: true, debugToken: '   ');
    expect((automatic as AndroidDebugProvider).debugToken, isNull);
  });

  test('installs the development provider without fetching a network token',
      () async {
    AndroidAppCheckProvider? selected;
    final initialized = await AppCheckConfig.initialize(
        enabled: true,
        activate: (provider) async {
          selected = provider;
        });
    expect(initialized, isTrue);
    expect(selected, isA<AndroidDebugProvider>());
  });

  test('provider failure does not prevent application startup', () async {
    expect(
        await AppCheckConfig.initialize(
            enabled: true,
            activate: (_) async {
              throw StateError('Fictional local provider failure');
            }),
        isFalse);
  });

  test('an unresponsive provider has a bounded startup wait', () async {
    final pending = Completer<void>();
    expect(
        await AppCheckConfig.initialize(
            enabled: true,
            activate: (_) => pending.future,
            timeout: const Duration(milliseconds: 10)),
        isFalse);
    pending.complete();
    await Future<void>.delayed(Duration.zero);
  });

  test('does not initialize an Android provider on other platforms', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var invoked = false;
    expect(
        await AppCheckConfig.initialize(
            enabled: true, activate: (_) async => invoked = true),
        isFalse);
    expect(invoked, isFalse);
  });
}
