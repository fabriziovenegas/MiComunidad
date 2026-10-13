import 'dart:convert';
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase client configuration supplied with --dart-define-from-file.
class DefaultFirebaseOptions {
  static const _encoded = String.fromEnvironment('FIREBASE_OPTIONS');
  static bool get isConfigured => _encoded.isNotEmpty;
  static FirebaseOptions get currentPlatform {
    if (!isConfigured) {
      throw StateError('Firebase no configurado.');
    }
    final platform = kIsWeb
        ? 'web'
        : switch (defaultTargetPlatform) {
            TargetPlatform.android => 'android',
            TargetPlatform.iOS => 'ios',
            TargetPlatform.macOS => 'macos',
            TargetPlatform.windows => 'windows',
            TargetPlatform.linux => 'linux',
            _ => throw UnsupportedError('Plataforma no configurada.'),
          };
    final all = jsonDecode(_encoded) as Map<String, dynamic>;
    final values = all[platform] as Map<String, dynamic>?;
    if (values == null) {
      throw StateError('Firebase no configurado para $platform.');
    }
    for (final key in ['apiKey', 'appId', 'messagingSenderId', 'projectId']) {
      if (values[key] is! String || (values[key] as String).isEmpty) {
        throw FormatException('Falta configuración Firebase: $key.');
      }
    }
    return FirebaseOptions(
        apiKey: values['apiKey'] as String,
        appId: values['appId'] as String,
        messagingSenderId: values['messagingSenderId'] as String,
        projectId: values['projectId'] as String,
        authDomain: values['authDomain'] as String?,
        storageBucket: values['storageBucket'] as String?,
        measurementId: values['measurementId'] as String?,
        iosBundleId: values['iosBundleId'] as String?);
  }
}
