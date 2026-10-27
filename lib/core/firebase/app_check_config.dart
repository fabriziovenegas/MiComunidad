import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// Install the Android provider before any application Firebase requests.
/// Development credentials are local build inputs, never production defaults.
class AppCheckConfig {
  AppCheckConfig._();

  static AndroidAppCheckProvider androidProvider({
    required bool debug,
    String debugToken = '',
  }) =>
      debug
          ? AndroidDebugProvider(
              debugToken: debugToken.trim().isEmpty ? null : debugToken.trim())
          : const AndroidPlayIntegrityProvider();

  static Future<bool> initialize({
    bool enabled = const bool.fromEnvironment('ENABLE_FIREBASE_APP_CHECK'),
    Future<void> Function(AndroidAppCheckProvider provider)? activate,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (!enabled || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    // The compiler removes the development-only token from release builds.
    final provider = androidProvider(
        debug: kDebugMode,
        debugToken: kDebugMode
            ? const String.fromEnvironment('FIREBASE_APP_CHECK_DEBUG_TOKEN')
            : '');
    try {
      await (activate ?? _activate)(provider).timeout(timeout);
      return true;
    } catch (_) {
      // App Check is optional until the project owner enables enforcement.
      // A provider failure must not turn a configured app into an empty screen.
      debugPrint('No se pudo iniciar App Check. La aplicación continuará.');
      return false;
    }
  }

  static Future<void> _activate(AndroidAppCheckProvider provider) =>
      FirebaseAppCheck.instance.activate(providerAndroid: provider);
}
