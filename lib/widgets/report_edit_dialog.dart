import 'package:flutter/material.dart';

import '../utils/text_encoding.dart';

class ReportEditDraft {
  const ReportEditDraft({
    required this.title,
    required this.description,
    required this.location,
    required this.category,
    required this.priority,
  });

  final String title;
  final String description;
  final String location;
  final String category;
  final String priority;

  Map<String, dynamic> toUpdateData() => {
        'title': title.trim(),
        'description': description.trim(),
        'location': location.trim(),
        'category': category,
        'priority': priority,
      };
}

typedef SaveReportEdit = Future<void> Function(ReportEditDraft draft);

class ReportEditDialog extends StatefulWidget {
  const ReportEditDialog({
    super.key,
    required this.data,
    this.onSave,
  });

  final Map<String, dynamic> data;
  final SaveReportEdit? onSave;

  @override
  State<ReportEditDialog> createState() => _ReportEditDialogState();
}

class _ReportEditDialogState extends State<ReportEditDialog> {
  static const _categories = [
    'seguridad',
    'obras',
    'iluminacion',
    'limpieza',
    'otro',
  ];
  static const _priorities = ['baja', 'media', 'alta'];

  late String _title;
  late String _description;
  late String _location;
  late String _category;
  late String _priority;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = readableText(widget.data['title']);
    _description = readableText(widget.data['description']);
    _location = readableText(widget.data['location']);

    final category = widget.data['category'] as String?;
    _category = _categories.contains(category) ? category! : 'otro';

    final priority = widget.data['priority'] as String?;
    _priority = _priorities.contains(priority) ? priority! : 'media';
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Editar mi reporte'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: _title,
                    onChanged: (value) => _title = value,
                    validator: _requiredText,
                    decoration: const InputDecoration(labelText: 'Título'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    initialValue: _description,
                    onChanged: (value) => _description = value,
                    validator: _requiredText,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(labelText: 'Descripción'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    initialValue: _location,
                    onChanged: (value) => _location = value,
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
                    onChanged: (value) {
                      if (value != null) setState(() => _category = value);
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
                    onChanged: (value) {
                      if (value != null) setState(() => _priority = value);
                    },
                  ),
                  if (widget.onSave == null) ...[
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lock_outline, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'El guardado se habilitará cuando existan permisos seguros para editar únicamente los reportes propios.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          Tooltip(
            message: widget.onSave == null
                ? 'Pendiente de habilitar permisos seguros en Firebase'
                : 'Guardar los cambios',
            child: FilledButton(
              onPressed: widget.onSave == null || _saving ? null : _saveChanges,
              child: Text(_saving ? 'Guardando…' : 'Guardar'),
            ),
          ),
        ],
      );

  String? _requiredText(String? value) => value == null || value.trim().isEmpty
      ? 'Este campo es obligatorio.'
      : null;

  Future<void> _saveChanges() async {
    if (widget.onSave == null || !_formKey.currentState!.validate()) return;
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
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'No se pudo guardar el reporte.';
        });
      }
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
