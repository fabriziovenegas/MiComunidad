import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/app_identity.dart';
import '../../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _hidePassword = true;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await AuthService.instance.signIn(
        email: _email.text,
        password: _password.text,
      );
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (error) {
      _showError(_authMessage(error.code));
    } catch (error) {
      _showError(_safeMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    var inputEmail = _email.text;
    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recuperar contraseña'),
        content: TextFormField(
          initialValue: inputEmail,
          onChanged: (value) => inputEmail = value,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Correo electrónico'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, inputEmail.trim()),
            child: const Text('Enviar enlace'),
          ),
        ],
      ),
    );
    if (email == null || email.isEmpty) return;
    try {
      await AuthService.instance.sendPasswordResetEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'Si el correo está asociado a una cuenta, recibirás un enlace para restablecer tu contraseña.',
        ),
      ));
    } catch (error) {
      _showError(
          'No se pudo enviar el enlace. Verifica el correo y la conexión.');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
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
                            onPressed: _loading ? null : _resetPassword,
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
