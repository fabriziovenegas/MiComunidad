import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/report_edit.dart';
import '../utils/text_encoding.dart';

export '../models/report_edit.dart' show ReportEditDraft;

typedef SaveReportEdit = Future<void> Function(ReportEditDraft draft);

class ReportEditDialog extends StatefulWidget {
  const ReportEditDialog({
    super.key,
    required this.data,
    this.onSave,
    this.onChangeStatus,
    this.allowResolvedContentEditing = false,
  });

  final Map<String, dynamic> data;
  final SaveReportEdit? onSave;
  final Future<String?> Function()? onChangeStatus;
  final bool allowResolvedContentEditing;

  @override
  State<ReportEditDialog> createState() => _ReportEditDialogState();
}

class _ReportEditDialogState extends State<ReportEditDialog> {
  static const _categories = ReportEditDraft.categories;
  static const _priorities = ReportEditDraft.priorities;

  late String _title;
  late String _description;
  late String _location;
  late String _category;
  late String _priority;
  late String _status;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  bool _changingStatus = false;
  bool get _busy => _saving || _changingStatus;
  bool get _canEditContent =>
      widget.onSave != null &&
      (reportContentIsEditable({...widget.data, 'status': _status}) ||
          (widget.allowResolvedContentEditing &&
              reportIsApprovedResolved({...widget.data, 'status': _status})));
  String? _error;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _title = readableText(widget.data['title']);
    _description = readableText(widget.data['description']);
    _location = readableText(widget.data['location']);
    _status = readableText(widget.data['status']);

    final category = widget.data['category'] as String?;
    _category = _categories.contains(category) ? category! : 'otro';

    final priority = widget.data['priority'] as String?;
    _priority = _priorities.contains(priority) ? priority! : 'media';
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: AlertDialog(
          title: Text(
              _canEditContent ? 'Editar mi reporte' : 'Actualizar reporte'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      enabled: !_busy,
                      readOnly: !_canEditContent,
                      initialValue: _title,
                      onChanged: (value) => _title = value,
                      validator: ReportEditDraft.validateTitle,
                      decoration: const InputDecoration(labelText: 'Título'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      enabled: !_busy,
                      readOnly: !_canEditContent,
                      initialValue: _description,
                      onChanged: (value) => _description = value,
                      validator: ReportEditDraft.validateDescription,
                      minLines: 3,
                      maxLines: 5,
                      decoration:
                          const InputDecoration(labelText: 'Descripción'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      enabled: !_busy,
                      readOnly: !_canEditContent,
                      initialValue: _location,
                      onChanged: (value) => _location = value,
                      validator: ReportEditDraft.validateLocation,
                      decoration: const InputDecoration(labelText: 'Ubicación'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _category,
                      decoration: const InputDecoration(labelText: 'Categoría'),
                      items: _categories
                          .map((value) => DropdownMenuItem(
                                value: value,
                                child: Text(_categoryLabel(value)),
                              ))
                          .toList(),
                      onChanged: _busy || !_canEditContent
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _category = value);
                              }
                            },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _priority,
                      decoration: const InputDecoration(labelText: 'Prioridad'),
                      items: _priorities
                          .map((value) => DropdownMenuItem(
                                value: value,
                                child: Text(_priorityLabel(value)),
                              ))
                          .toList(),
                      onChanged: _busy || !_canEditContent
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _priority = value);
                              }
                            },
                    ),
                    const SizedBox(height: 18),
                    if (_statusMessage != null) ...[
                      Text(_statusMessage!),
                      const SizedBox(height: 12),
                    ],
                    if (widget.onChangeStatus != null) ...[
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _changeStatus,
                          icon: const Icon(Icons.sync_outlined),
                          label: Text(_changingStatus
                              ? 'Actualizando…'
                              : 'Actualizar estado'),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                              !_canEditContent
                                  ? Icons.lock_outline
                                  : Icons.info_outline,
                              size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              !_canEditContent
                                  ? (_status == 'resuelto'
                                      ? 'El contenido de un reporte resuelto es de solo lectura. El administrador puede actualizar su estado para reabrirlo.'
                                      : 'Este reporte no permite editar su contenido.')
                                  : 'Los cambios serán visibles para quienes tengan acceso a este reporte.',
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            Tooltip(
              message: !_canEditContent
                  ? 'Este reporte no permite editar su contenido'
                  : 'Guardar los cambios',
              child: FilledButton(
                onPressed: !_canEditContent || _busy ? null : _saveChanges,
                child: Text(_saving ? 'Guardando…' : 'Guardar'),
              ),
            ),
          ],
        ),
      );

  Future<void> _saveChanges() async {
    if (_busy || !_canEditContent || !_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave!(ReportEditDraft(
        title: _title,
        description: _description,
        location: _location,
        category: _category,
        priority: _priority,
      ));
      if (mounted) {
        setState(() => _saving = false);
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = switch (error) {
            FirebaseException(code: 'permission-denied') =>
              'No tienes permiso para guardar este reporte. Puede haber finalizado o faltar habilitar la regla de edición. Tus cambios se conservan en este formulario.',
            FirebaseException(code: 'not-found') =>
              'El reporte ya no existe. Tus cambios se conservan en este formulario.',
            FirebaseException(code: 'unauthenticated') =>
              'Debes iniciar sesión para guardar. Tus cambios se conservan en este formulario.',
            _ =>
              'No se pudo guardar el reporte. Tus cambios se conservan en este formulario; puedes reintentar.',
          };
        });
      }
    }
  }

  Future<void> _changeStatus() async {
    if (_busy || widget.onChangeStatus == null) return;
    setState(() {
      _changingStatus = true;
      _error = null;
    });
    try {
      final status = await widget.onChangeStatus!();
      if (mounted && status != null) {
        setState(() {
          _status = status;
          _statusMessage = 'Estado actualizado: ${switch (status) {
            'resuelto' => 'Resuelto',
            'en_proceso' => 'En Proceso',
            _ => 'Por Atender',
          }}.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'No se pudo actualizar el estado. Tus cambios de contenido se conservan en este formulario.');
      }
    } finally {
      if (mounted) setState(() => _changingStatus = false);
    }
  }

  static String _categoryLabel(String value) => switch (value) {
        'seguridad' => 'Seguridad',
        'obras' => 'Obras',
        'iluminacion' => 'Iluminación',
        'limpieza' => 'Limpieza',
        _ => 'Otro',
      };

  static String _priorityLabel(String value) => switch (value) {
        'alta' => 'Alta',
        'baja' => 'Baja',
        _ => 'Media',
      };
}
