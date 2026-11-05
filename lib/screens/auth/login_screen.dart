import '../../widgets/online_action_dialog.dart';
import '../../widgets/password_reset_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_identity.dart';
import '../../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen(
      {super.key, this.sendResetEmail, this.isOffline, this.signIn});
  final Future<void> Function(String)? sendResetEmail;
  final Future<bool> Function()? isOffline;
  final Future<void> Function(
      {required String email, required String password})? signIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _hidePassword = true;
  bool _loading = false;
  bool _resetting = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading || _resetting || !_formKey.currentState!.validate()) return;
    final email = _email.text, password = _password.text;
    setState(() => _loading = true);
    try {
      final signedIn = await runOnlineAction(context,
          actionKey: 'sign-in',
          isOffline: widget.isOffline,
          offlineMessage: 'Necesitas conexión para iniciar sesión',
          slowMessage:
              'El inicio de sesión está tardando. Verifica tu conexión',
          successMessage: null,
          errorMessage: (error) => error is FirebaseAuthException
              ? _authMessage(error.code)
              : _safeMessage(error),
          action: () => (widget.signIn ?? AuthService.instance.signIn)(
              email: email, password: password));
      if (signedIn && mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_resetting || _loading) return;
    setState(() => _resetting = true);
    try {
      await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => PasswordResetDialog(
              initialEmail: _email.text,
              isOffline: widget.isOffline,
              sendEmail: (email) => (widget.sendResetEmail ??
                  AuthService.instance.sendPasswordResetEmail)(email)));
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  String _authMessage(String code) => switch (code) {
        'invalid-credential' => 'Correo o contraseña incorrectos.',
        'too-many-requests' => 'Demasiados intentos. Inténtalo más tarde.',
        'network-request-failed' => 'No hay conexión. Revisa tu internet.',
        _ => 'No se pudo iniciar sesión.',
      };

  String _safeMessage(Object error) {
    if (error is AuthFlowException) return error.message;
    return 'No se pudo iniciar sesión. Inténtalo nuevamente.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        const CircleAvatar(
                          radius: 36,
                          backgroundColor: AppColors.primaryContainer,
                          child: Icon(Icons.location_city,
                              size: 38, color: AppColors.onPrimaryContainer),
                        ),
                        const SizedBox(height: 18),
                        Text(AppIdentity.appName,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text('Inicia sesión para continuar'),
                        const SizedBox(height: 28),
                        TextFormField(
                          controller: _email,
                          enabled: !_loading,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                              labelText: 'Correo electrónico',
                              prefixIcon: Icon(Icons.email_outlined)),
                          validator: (value) =>
                              value == null || !value.contains('@')
                                  ? 'Ingresa un correo válido.'
                                  : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _password,
                          enabled: !_loading,
                          obscureText: _hidePassword,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => _login(),
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _hidePassword
                                  ? 'Mostrar contraseña'
                                  : 'Ocultar contraseña',
                              onPressed: () => setState(
                                  () => _hidePassword = !_hidePassword),
                              icon: Icon(_hidePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                            ),
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? 'Ingresa tu contraseña.'
                              : null,
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _loading ? null : _login,
                            icon: _loading
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.login),
                            label: Text(
                                _loading ? 'Ingresando…' : 'Iniciar sesión'),
                          ),
                        ),
                        TextButton(
                            onPressed:
                                _loading || _resetting ? null : _resetPassword,
                            child: const Text('¿Olvidaste tu contraseña?')),
                        const Divider(height: 30),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text('¿Aún no eres vecino?'),
                            TextButton(
                                onPressed: () =>
                                    Navigator.pushNamed(context, '/signup'),
                                child: const Text('Solicitar ingreso')),
                          ],
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _loading
                              ? null
                              : () => Navigator.pushNamed(
                                    context,
                                    '/request-status',
                                  ),
                          icon: const Icon(Icons.assignment_outlined),
                          label: const Text('Ver estado de mi solicitud'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
