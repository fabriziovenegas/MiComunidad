import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/services/upload_connection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(UploadConnection.channel, null));

  for (final offline in [true, false]) {
    test('Android confirmed offline=$offline does not issue an HTTP probe',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(UploadConnection.channel, (call) async {
        expect(call.method, 'isOffline');
        return offline;
      });
      expect(
          await UploadConnection.isOffline(
              probe: () async => throw StateError('Unnecessary probe')),
          offline);
    });
  }
  test('unknown native state falls back to reachability', () async {
    expect(
        await UploadConnection.isOffline(
            networkState: () async => null, probe: () async => true),
        true);
    expect(
        await UploadConnection.isOffline(
            networkState: () async => null, probe: () async => false),
        false);
  });
  test('missing native method falls back without blocking a hot restart',
      () async {
    expect(
        await UploadConnection.isOffline(
            networkState: () async => throw MissingPluginException(),
            probe: () async => false),
        false);
  });
  test('probe timeout/unknown failure is not proof of lost internet', () async {
    expect(
        await UploadConnection.isOffline(
            networkState: () async => null,
            probe: () async => throw TimeoutException('Slow network')),
        false);
  });
}
