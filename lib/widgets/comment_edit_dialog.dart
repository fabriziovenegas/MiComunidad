import 'package:flutter/material.dart';
import 'limited_text_form_field.dart';
import 'online_action_dialog.dart';

class CommentEditDialog extends StatefulWidget {
  const CommentEditDialog(
      {super.key,
      required this.initialText,
      required this.onSave,
      this.actionKey,
      this.isOffline});
  final String initialText;
  final String? actionKey;
  final Future<bool> Function()? isOffline;
  final Future<void> Function(String) onSave;
  @override
  State<CommentEditDialog> createState() => _CommentEditDialogState();
}

class _CommentEditDialogState extends State<CommentEditDialog> {
  final _form = GlobalKey<FormState>();
  late String _text = widget.initialText;
  bool _saving = false;
  bool _slow = false;
  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _saving = true;
      _slow = false;
    });
    final saved = await runOnlineAction(context,
        actionKey: widget.actionKey ??
            'edit-comment:${identityHashCode(widget.onSave)}',
        isOffline: widget.isOffline,
        slowMessage:
            'El guardado del comentario está tardando. Verifica tu conexión.',
        successMessage: 'Comentario actualizado.',
        onSlow: () {
          if (mounted) setState(() => _slow = true);
        },
        action: () => widget.onSave(_text.trim()));
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving || _slow,
      child: AlertDialog(
        title: const Text('Editar comentario'),
        content: SingleChildScrollView(
            child: Form(
                key: _form,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  LimitedTextFormField(
                      characterLimit: 1000,
                      initialValue: _text,
                      enabled: !_saving,
                      minLines: 3,
                      maxLines: 6,
                      onChanged: (value) => _text = value,
                      decoration:
                          const InputDecoration(labelText: 'Comentario'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Escribe un comentario.'
                              : null),
                ]))),
        actions: [
          TextButton(
              onPressed:
                  _saving && !_slow ? null : () => Navigator.pop(context),
              child: Text(_saving && _slow ? 'Cerrar' : 'Cancelar')),
          FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving
                  ? (_slow ? 'Esperando confirmación…' : 'Guardando…')
                  : 'Guardar'))
        ],
      ));
}
