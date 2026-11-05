import 'package:flutter/material.dart';
import 'online_action_dialog.dart';

/// Keeps the explicit confirmation and the existing staged deletion workflow.
class PermanentDeleteDialog extends StatefulWidget {
  const PermanentDeleteDialog(
      {super.key,
      required this.entity,
      required this.name,
      required this.actionKey,
      required this.onDelete,
      this.details,
      this.isOffline});
  final String entity, name, actionKey;
  final Future<void> Function() onDelete;
  final String Function(Object)? details;
  final Future<bool> Function()? isOffline;
  @override
  State<PermanentDeleteDialog> createState() => _PermanentDeleteDialogState();
}

class _PermanentDeleteDialogState extends State<PermanentDeleteDialog> {
  String _confirmation = '';
  bool _busy = false, _slow = false;
  String? _error;
  Future<void> _delete() async {
    if (_busy || _confirmation != 'CONFIRMAR') return;
    setState(() {
      _busy = true;
      _slow = false;
      _error = null;
    });
    final saved = await runOnlineAction(context,
        actionKey: widget.actionKey,
        isOffline: widget.isOffline,
        slowMessage:
            'La eliminación del ${widget.entity} está tardando. Verifica tu conexión.',
        successMessage:
            '${widget.entity == 'proyecto' ? 'Proyecto' : 'Reporte'} eliminado definitivamente.',
        onSlow: () {
      if (mounted) setState(() => _slow = true);
    }, action: () async {
      try {
        await widget.onDelete();
      } catch (error) {
        if (mounted) {
          setState(() => _error = widget.details?.call(error) ??
              'No se pudo completar la eliminación. Revisa su estado antes de reintentar.');
        }
        rethrow;
      }
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (saved) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy || _slow,
      child: AlertDialog(
          title: Text('Eliminar ${widget.entity} definitivamente'),
          content: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('La eliminación de “${widget.name}” es irreversible.'),
                const SizedBox(height: 12),
                const Text('Escribe CONFIRMAR para validar la intención.'),
                const SizedBox(height: 8),
                TextField(
                    enabled: !_busy,
                    onChanged: (value) => setState(() => _confirmation = value),
                    decoration: const InputDecoration(labelText: 'CONFIRMAR')),
                const SizedBox(height: 12),
                Text(
                    _confirmation == 'CONFIRMAR'
                        ? widget.entity == 'proyecto'
                            ? 'Se eliminarán el proyecto, sus fotos, documentos y comentarios asociados. Esta acción no se puede deshacer.'
                            : 'Se eliminarán todas las fotografías y los comentarios asociados. Esta acción no se puede deshacer.'
                        : 'La palabra debe coincidir exactamente.',
                    style: TextStyle(
                        color: _confirmation == 'CONFIRMAR'
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.error)),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error))
                ],
              ])),
          actions: [
            TextButton(
                onPressed: _busy && !_slow
                    ? null
                    : () => Navigator.pop(context, false),
                child: Text(_busy ? 'Cerrar' : 'Cancelar')),
            FilledButton(
                onPressed:
                    _busy || _confirmation != 'CONFIRMAR' ? null : _delete,
                child:
                    Text(_busy ? 'Eliminando...' : 'Eliminar definitivamente')),
          ]));
}
