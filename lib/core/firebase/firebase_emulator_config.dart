import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

class FirebaseEmulatorConfig {
  FirebaseEmulatorConfig._();

  static const enabled =
      bool.fromEnvironment('USE_FIREBASE_EMULATORS', defaultValue: false);

  static void connect() {
    if (!enabled) return;

    final host = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : '127.0.0.1';

    FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    FirebaseStorage.instance.useStorageEmulator(host, 9199);
    FirebaseFunctions.instanceFor(region: 'southamerica-east1')
        .useFunctionsEmulator(host, 5001);
  }
}
