import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

class ContentCommentComposer extends StatefulWidget {
  const ContentCommentComposer({
    super.key,
    required this.onSend,
    this.enabled = true,
  });

  final Future<void> Function(String text) onSend;
  final bool enabled;

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
              child: TextField(
                controller: _controller,
                enabled: widget.enabled && !_saving,
                minLines: 1,
                maxLines: 3,
                decoration:
                    const InputDecoration(hintText: 'Escribe un comentario…'),
              ),
            ),
            IconButton.filled(
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
    if (text.isEmpty || text.length > 1000) {
      setState(() => _error = 'Escribe entre 1 y 1000 caracteres.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSend(text);
      if (mounted) {
        _controller.clear();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Comentario publicado.')));
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
