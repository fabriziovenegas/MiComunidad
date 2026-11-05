import 'package:flutter/material.dart';
import 'online_action_dialog.dart';

class PasswordResetDialog extends StatefulWidget {
  const PasswordResetDialog(
      {super.key,
      required this.initialEmail,
      required this.sendEmail,
      this.isOffline});
  final String initialEmail;
  final Future<void> Function(String) sendEmail;
  final Future<bool> Function()? isOffline;
  @override
  State<PasswordResetDialog> createState() => _PasswordResetDialogState();
}

class _PasswordResetDialogState extends State<PasswordResetDialog> {
  final _form = GlobalKey<FormState>();
  late String _email = widget.initialEmail;
  bool _busy = false, _slow = false;
  Future<void> _send() async {
    if (_busy || _form.currentState?.validate() != true) return;
    final email = _email.trim();
    setState(() {
      _busy = true;
      _slow = false;
    });
    final sent = await runOnlineAction(context,
        actionKey: 'password-reset:${email.toLowerCase()}',
        action: () => widget.sendEmail(email),
        isOffline: widget.isOffline,
        offlineMessage: 'Necesitas conexión para recuperar tu contraseña',
        slowMessage: 'El envío del enlace está tardando. Verifica tu conexión.',
        successMessage:
            'Si el correo está asociado a una cuenta, recibirás un enlace para restablecer tu contraseña.',
        errorMessage: (_) =>
            'No se pudo enviar el enlace. Verifica el correo y la conexión.',
        onSlow: () {
          if (mounted) setState(() => _slow = true);
        });
    if (!mounted) return;
    setState(() => _busy = false);
    if (sent) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy || _slow,
      child: AlertDialog(
          title: const Text('Recuperar contraseña'),
          content: Form(
              key: _form,
              child: TextFormField(
                  initialValue: _email,
                  enabled: !_busy,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (value) => _email = value,
                  onFieldSubmitted: (_) => _send(),
                  validator: (value) => value != null &&
                          RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                              .hasMatch(value.trim())
                      ? null
                      : 'Ingresa un correo válido.',
                  decoration:
                      const InputDecoration(labelText: 'Correo electrónico'))),
          actions: [
            TextButton(
                onPressed:
                    _busy && !_slow ? null : () => Navigator.pop(context),
                child: Text(_busy && _slow ? 'Cerrar' : 'Cancelar')),
            FilledButton(
                onPressed: _busy ? null : _send,
                child: Text(_busy ? 'Enviando…' : 'Enviar enlace'))
          ]));
}
