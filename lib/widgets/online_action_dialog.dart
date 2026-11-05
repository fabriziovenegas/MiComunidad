import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../services/upload_connection.dart';
import 'upload_error_notice.dart';

final _activeActions = <String>{};

/// Keeps a slow action alive without queuing another one when its UI is closed.
Future<bool> runOnlineAction(
  BuildContext context, {
  required String actionKey,
  required Future<void> Function() action,
  required String? successMessage,
  String slowMessage = 'La operación está tardando. Espera un momento',
  String offlineMessage = 'Necesitas conexión para realizar esta acción',
  Future<bool> Function()? isOffline,
  VoidCallback? onSlow,
  String Function(Object)? errorMessage,
}) async {
  if (!_activeActions.add(actionKey)) {
    showWarningNotice(
        context, 'Esta operación sigue en curso. Espera un momento.');
    return false;
  }
  final notices = Overlay.of(context, rootOverlay: true);
  final timer = Timer(const Duration(seconds: 5), () {
    if (context.mounted) {
      onSlow?.call();
      showWarningNotice(context, slowMessage);
    }
  });
  try {
    if (await (isOffline ?? UploadConnection.isOffline)()) {
      if (context.mounted) {
        showUploadError(context, offlineMessage);
      }
      return false;
    }
    await action();
    if (notices.mounted && successMessage != null) {
      showSuccessNotice(notices.context, successMessage, overlay: notices);
    } else if (notices.mounted) {
      dismissUploadError();
    }
    return true;
  } catch (error) {
    if (notices.mounted) {
      final code = error is FirebaseException ? error.code : '';
      showUploadError(
          notices.context,
          errorMessage?.call(error) ??
              switch (code) {
                'unavailable' ||
                'network-request-failed' =>
                  'No se pudo conectar. Revisa tu conexión y vuelve a intentarlo.',
                'permission-denied' ||
                'unauthenticated' =>
                  'Tu cuenta no tiene permiso para realizar esta acción.',
                'not-found' => 'El contenido ya no está disponible.',
                _ =>
                  'No se pudo confirmar la operación. Revisa su estado antes de reintentar.',
              },
          overlay: notices);
    }
    return false;
  } finally {
    timer.cancel();
    _activeActions.remove(actionKey);
  }
}

Future<bool?> showOnlineActionConfirmation(
  BuildContext context, {
  required String actionKey,
  required String title,
  required String question,
  required String confirmLabel,
  required String successMessage,
  String slowMessage = 'La operación está tardando. Espera un momento',
  required Future<void> Function() action,
  Future<bool> Function()? isOffline,
  String Function(Object)? errorMessage,
}) =>
    showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _OnlineActionDialog(
            actionKey: actionKey,
            title: title,
            question: question,
            confirmLabel: confirmLabel,
            successMessage: successMessage,
            slowMessage: slowMessage,
            action: action,
            errorMessage: errorMessage,
            isOffline: isOffline));

class _OnlineActionDialog extends StatefulWidget {
  const _OnlineActionDialog(
      {required this.actionKey,
      required this.title,
      required this.question,
      required this.confirmLabel,
      required this.successMessage,
      required this.slowMessage,
      required this.action,
      this.errorMessage,
      this.isOffline});
  final String actionKey, title, question, confirmLabel, successMessage;
  final String slowMessage;
  final Future<void> Function() action;
  final Future<bool> Function()? isOffline;
  final String Function(Object)? errorMessage;
  @override
  State<_OnlineActionDialog> createState() => _OnlineActionDialogState();
}

class _OnlineActionDialogState extends State<_OnlineActionDialog> {
  bool _busy = false, _slow = false;
  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _slow = false;
    });
    final saved = await runOnlineAction(context,
        actionKey: widget.actionKey,
        action: widget.action,
        successMessage: widget.successMessage,
        slowMessage: widget.slowMessage,
        errorMessage: widget.errorMessage,
        isOffline: widget.isOffline, onSlow: () {
      if (mounted) setState(() => _slow = true);
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (saved) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy || _slow,
      child: AlertDialog(
          title: Text(widget.title),
          content: Text(widget.question),
          actions: [
            TextButton(
                onPressed: _busy && !_slow
                    ? null
                    : () => Navigator.pop(context, false),
                child: Text(_busy ? 'Cerrar' : 'Cancelar')),
            FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(
                    _busy ? 'Esperando confirmación…' : widget.confirmLabel)),
          ]));
}
