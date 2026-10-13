import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../screens/home_screen.dart';
import '../../screens/onboarding/welcome_screen.dart';
import '../../services/auth_service.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<firebase.User?>(
      stream: AuthService.instance.authStateChanges,
      builder: (context, auth) {
        if (auth.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final user = auth.data;
        if (user == null || user.isAnonymous) return const WelcomeScreen();
        return StreamBuilder<AppUser?>(
          stream: AuthService.instance.profileStream(user.uid),
          builder: (context, profile) {
            if (profile.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }
            if (profile.hasError ||
                profile.data == null ||
                !profile.data!.isApproved) {
              return _InvalidProfile(
                  message: profile.hasError
                      ? 'No se pudo cargar el perfil.'
                      : 'La cuenta no está habilitada.');
            }
            return HomeScreen(user: profile.data!);
          },
        );
      },
    );
  }
}

class _InvalidProfile extends StatelessWidget {
  const _InvalidProfile({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_clock, size: 64),
              const SizedBox(height: 12),
              Text(message),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: AuthService.instance.signOut,
                  child: const Text('Cerrar sesión'))
            ]),
          ),
        ),
      );
}
