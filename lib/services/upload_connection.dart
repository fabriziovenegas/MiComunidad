import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

/// A slow upload is not proof of lost connectivity. Prefer Android's validated
/// network state; if unavailable, check HTTPS reachability without credentials.
class UploadConnection {
  static const channel = MethodChannel('micomunidad/upload_connection');
  static const _events = EventChannel('micomunidad/upload_connection_changes');
  static Stream<bool?> get changes =>
      _events.receiveBroadcastStream().map((value) => value as bool?);

  static Future<bool> isOffline({
    Future<bool?> Function()? networkState,
    Future<bool> Function()? probe,
  }) async {
    try {
      final offline = await (networkState ??
              () => channel.invokeMethod<bool>('isOffline'))()
          .timeout(const Duration(seconds: 2));
      if (offline != null) return offline;
    } catch (_) {
      // Older native builds and unsupported platforms can still check HTTPS.
    }
    try {
      return await (probe ?? _probe)();
    } catch (_) {
      // An unknown result must not label a slow connection as disconnected.
      return false;
    }
  }

  static Future<bool> _probe() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      return await (() async {
        final request = await client
            .headUrl(Uri.https('firebasestorage.googleapis.com', '/'));
        final response = await request.close();
        await response.drain<void>();
        return false; // Any HTTPS status confirms reachability, even 404.
      })()
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
    } on SocketException {
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
