import 'limited_text_form_field.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../services/pending_send.dart';
import 'upload_error_notice.dart';

class ContentCommentComposer extends StatefulWidget {
  const ContentCommentComposer({
    super.key,
    this.onSend,
    this.onSendPending,
    this.enabled = true,
    this.projectStyle = false,
  }) : assert((onSend == null) != (onSendPending == null));

  final Future<void> Function(String text)? onSend;
  final Future<PendingSendResult> Function(String text)? onSendPending;
  final bool enabled;
  final bool projectStyle;

  @override
  State<ContentCommentComposer> createState() => _ContentCommentComposerState();
}

class _ContentCommentComposerState extends State<ContentCommentComposer> {
  final _controller = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: LimitedTextFormField(
                characterLimit: 1000,
                controller: _controller,
                enabled: widget.enabled && !_saving,
                minLines: 1,
                maxLines: 3,
                decoration:
                    const InputDecoration(hintText: 'Escribe un comentario…'),
              ),
            ),
            if (widget.projectStyle) const SizedBox(width: 8),
            IconButton.filled(
              style: widget.projectStyle
                  ? IconButton.styleFrom(
                      backgroundColor: const Color(0xFF276749),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.all(12),
                    )
                  : null,
              tooltip: 'Enviar comentario',
              onPressed: widget.enabled && !_saving ? _send : null,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
            ),
          ]),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      );

  Future<void> _send() async {
    if (_saving || !widget.enabled) return;
    final text = _controller.text.trim();
    if (text.isEmpty || _controller.text.length > 1000) {
      setState(() => _error = 'Escribe entre 1 y 1000 caracteres.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final pendingSend = widget.onSendPending;
      final PendingSendResult? result;
      if (pendingSend != null) {
        result = await pendingSend(text);
      } else {
        await widget.onSend!(text);
        result = null;
      }
      if (mounted) {
        _controller.clear();
        if (result == null) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Comentario publicado.')));
        } else if (result.state == PendingSendState.blocked) {
          showUploadError(context,
              'Comentario guardado en este dispositivo. ${result.reason} Revisa los pendientes.');
        } else {
          showSuccessNotice(
              context,
              result.state == PendingSendState.sent
                  ? 'Comentario publicado.'
                  : 'Comentario guardado. Se enviará cuando haya conexión.');
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is FirebaseException &&
                error.code == 'permission-denied'
            ? 'El reporte ya no admite comentarios, puede estar en eliminación o no tienes acceso. Tu texto se conserva.'
            : 'No se pudo publicar el comentario. Tu texto se conserva para reintentar.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
