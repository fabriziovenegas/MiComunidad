import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/auth/auth_wrapper.dart';
import 'core/theme/app_theme.dart';
import 'config/app_identity.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/request_status_screen.dart';
import 'screens/auth/request_success_screen.dart';
import 'screens/auth/signup_screen.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppIdentity.appName,
      theme: AppTheme.light,
      locale: const Locale('es', 'PE'),
      supportedLocales: const [Locale('es', 'PE')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const AuthWrapper(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/signup': (_) => const SignupScreen(),
        '/request-status': (_) => const RequestStatusScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/request-success') {
          final raw = settings.arguments as Map<String, dynamic>? ?? const {};
          final summary =
              raw.map((key, value) => MapEntry(key, value.toString()));
          return MaterialPageRoute(
              builder: (_) => RequestSuccessScreen(summary: summary));
        }
        return null;
      },
    );
  }
}
