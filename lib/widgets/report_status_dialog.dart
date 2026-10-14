import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

/// Returns the selected status only after the server confirms its own write.
class ReportStatusDialog extends StatefulWidget {
  const ReportStatusDialog({
    super.key,
    required this.initialStatus,
    required this.onSave,
  });

  final String initialStatus;
  final Future<void> Function(String status) onSave;

  @override
  State<ReportStatusDialog> createState() => _ReportStatusDialogState();
}

class _ReportStatusDialogState extends State<ReportStatusDialog> {
  static const _statuses = ['pendiente', 'en_proceso', 'resuelto'];
  late String _status;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _status = _statuses.contains(widget.initialStatus)
        ? widget.initialStatus
        : 'pendiente';
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
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
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Guardando…' : 'Guardar'),
            ),
          ],
        ),
      );

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_status);
      if (mounted) {
        setState(() => _saving = false);
        Navigator.pop(context, _status);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is FirebaseException &&
                  error.code == 'permission-denied'
              ? 'No se pudo guardar el estado: Firebase rechazó esta actualización. El estado seleccionado se conserva para reintentar.'
              : 'No se pudo guardar el estado. Puedes reintentar sin volver a seleccionarlo.';
        });
      }
    }
  }
}
