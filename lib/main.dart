import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/firebase/firebase_emulator_config.dart';
import 'core/firebase/app_check_config.dart';
import 'firebase_options.dart';
import 'services/pending_upload_service.dart';
import 'services/pending_report_service.dart';
import 'services/pending_content_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!DefaultFirebaseOptions.isConfigured) {
    runApp(const _UnconfiguredApp());
    return;
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await AppCheckConfig.initialize();
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    FirebaseEmulatorConfig.connect();
    PendingUploadService.instance.start();
    PendingReportService.instance.start();
    PendingContentService.instance.start();
    debugPrint('Firebase inicializado correctamente.');
  } catch (error) {
    debugPrint('No se pudo inicializar Firebase.');
    runApp(const _UnconfiguredApp());
    return;
  }

  runApp(const MyApp());
}

class _UnconfiguredApp extends StatelessWidget {
  const _UnconfiguredApp();
  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: Scaffold(
            body: Center(
                child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
              'Firebase no configurado. Configura tu propio proyecto para continuar.'),
        ))),
      );
}
