import 'package:flutter/material.dart';
import 'limited_text_form_field.dart';

class CommentEditDialog extends StatefulWidget {
  const CommentEditDialog(
      {super.key, required this.initialText, required this.onSave});
  final String initialText;
  final Future<void> Function(String) onSave;
  @override
  State<CommentEditDialog> createState() => _CommentEditDialogState();
}

class _CommentEditDialogState extends State<CommentEditDialog> {
  final _form = GlobalKey<FormState>();
  late String _text = widget.initialText;
  bool _saving = false;
  String? _error;
  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'No se pudo guardar. Revisa tu conexión o vuelve a abrir el comentario. Tus cambios se conservan aquí.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
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
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                ]))),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Guardando…' : 'Guardar'))
        ],
      ));
}
