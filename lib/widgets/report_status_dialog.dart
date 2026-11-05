import 'online_action_dialog.dart';
import 'package:flutter/material.dart';

/// Returns the selected status only after the server confirms its own write.
class ReportStatusDialog extends StatefulWidget {
  const ReportStatusDialog({
    super.key,
    required this.initialStatus,
    required this.onSave,
    this.isOffline,
    this.actionKey,
  });

  final String initialStatus;
  final Future<bool> Function()? isOffline;
  final String? actionKey;
  final Future<void> Function(String status) onSave;

  @override
  State<ReportStatusDialog> createState() => _ReportStatusDialogState();
}

class _ReportStatusDialogState extends State<ReportStatusDialog> {
  static const _statuses = ['pendiente', 'en_proceso', 'resuelto'];
  late String _status;
  bool _saving = false;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _status = _statuses.contains(widget.initialStatus)
        ? widget.initialStatus
        : 'pendiente';
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving || _slow,
        child: AlertDialog(
          title: const Text('Actualizar reporte'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Estado'),
                items: _statuses
                    .map((value) => DropdownMenuItem(
                          value: value,
                          child: Text(switch (value) {
                            'en_proceso' => 'En Proceso',
                            'resuelto' => 'Resuelto',
                            _ => 'Por Atender',
                          }),
                        ))
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) setState(() => _status = value);
                      },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed:
                  _saving && !_slow ? null : () => Navigator.pop(context),
              child: Text(_saving ? 'Cerrar' : 'Cancelar'),
            ),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving
                  ? (_slow ? 'Esperando confirmación…' : 'Guardando…')
                  : 'Guardar'),
            ),
          ],
        ),
      );

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _slow = false;
    });
    final saved = await runOnlineAction(context,
        actionKey: widget.actionKey ??
            'report-status:${identityHashCode(widget.onSave)}',
        action: () => widget.onSave(_status),
        successMessage: 'Estado actualizado.',
        isOffline: widget.isOffline,
        onSlow: () {
          if (mounted) setState(() => _slow = true);
        });
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) Navigator.pop(context, _status);
  }
}
