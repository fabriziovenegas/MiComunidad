import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/community_service.dart';
import '../../widgets/content_detail_sheet.dart';

class ArchivedProjectsScreen extends StatefulWidget {
  const ArchivedProjectsScreen({
    super.key,
    required this.user,
  });

  final AppUser user;

  @override
  State<ArchivedProjectsScreen> createState() => _ArchivedProjectsScreenState();
}

class _ArchivedProjectsScreenState extends State<ArchivedProjectsScreen> {
  String? _deletingProjectId;

  @override
  Widget build(BuildContext context) {
    if (!widget.user.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Archivados')),
        body: const Center(
          child: Text('Esta sección es exclusiva para administradores.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Proyectos archivados')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: CommunityService.instance.archivedProjects(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('No se pudieron cargar los proyectos archivados.'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final archived = snapshot.data!.docs.toList()
            ..sort((left, right) {
              final leftDate = left.data()['trashedAt'] as Timestamp?;
              final rightDate = right.data()['trashedAt'] as Timestamp?;
              return (rightDate?.millisecondsSinceEpoch ?? 0)
                  .compareTo(leftDate?.millisecondsSinceEpoch ?? 0);
            });
          if (archived.isEmpty) {
            return const Center(child: Text('No hay proyectos archivados.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: archived.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final document = archived[index];
              final data = document.data();
              final progress = (data['progress'] as num?)?.toDouble() ?? 0;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              data['title'] as String? ?? 'Proyecto',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          Chip(
                            label: Text(_statusLabel(
                              data['status'] as String? ?? 'pendiente',
                            )),
                          ),
                        ],
                      ),
                      if ((data['location'] as String? ?? '').isNotEmpty)
                        Text(data['location'] as String),
                      const SizedBox(height: 8),
                      Text(data['description'] as String? ?? ''),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              value: progress.clamp(0, 100) / 100,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text('${progress.clamp(0, 100).round()}%'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _openProject(
                              context,
                              document,
                            ),
                            icon: const Icon(Icons.visibility_outlined),
                            label: const Text('Ver información'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => _restoreProject(
                              context,
                              document,
                            ),
                            icon: const Icon(Icons.restore),
                            label: const Text('Restaurar'),
                          ),
                          TextButton.icon(
                            onPressed: _deletingProjectId == null
                                ? () => _confirmPermanentDeletion(
                                      context,
                                      document,
                                    )
                                : null,
                            icon: const Icon(Icons.delete_forever_outlined),
                            label: Text(_deletingProjectId == document.id
                                ? 'Eliminando...'
                                : 'Eliminación definitiva'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static String _statusLabel(String value) => switch (value) {
        'en_proceso' => 'En proceso',
        'finalizado' => 'Finalizado',
        _ => 'Pendiente',
      };

  void _openProject(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ContentDetailSheet(
        collection: 'projects',
        documentId: document.id,
        title: data['title'] as String? ?? 'Proyecto',
        user: widget.user,
        readOnly: true,
      ),
    );
  }

  Future<void> _restoreProject(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final data = document.data();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restaurar proyecto'),
        content: Text(
          '¿Deseas restaurar “${data['title'] as String? ?? 'Proyecto'}”? Volverá a aparecer en la lista normal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await CommunityService.instance.restoreProject(document.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Proyecto restaurado.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo restaurar el proyecto: $error')),
        );
      }
    }
  }

  Future<void> _confirmPermanentDeletion(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final data = document.data();
    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PermanentDeleteDialog(
        projectTitle: data['title'] as String? ?? 'Proyecto',
        onDelete: () => _deleteProject(document.id),
      ),
    );
    if (deleted == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proyecto eliminado definitivamente.')),
      );
    }
  }

  Future<void> _deleteProject(String projectId) async {
    if (_deletingProjectId != null) {
      throw const ProjectDeletionException(
        failedStep: 'iniciar la eliminación',
        completedSteps: [],
        cause: 'Ya hay otra eliminación en curso.',
      );
    }

    setState(() => _deletingProjectId = projectId);
    try {
      await CommunityService.instance
          .permanentlyDeleteArchivedProject(projectId);
    } finally {
      if (mounted) setState(() => _deletingProjectId = null);
    }
  }
}

class _PermanentDeleteDialog extends StatefulWidget {
  const _PermanentDeleteDialog({
    required this.projectTitle,
    required this.onDelete,
  });

  final String projectTitle;
  final Future<void> Function() onDelete;

  @override
  State<_PermanentDeleteDialog> createState() => _PermanentDeleteDialogState();
}

class _PermanentDeleteDialogState extends State<_PermanentDeleteDialog> {
  String _confirmation = '';
  bool _deleting = false;
  String? _errorMessage;

  Future<void> _delete() async {
    if (_deleting || _confirmation != 'CONFIRMAR') return;
    setState(() {
      _deleting = true;
      _errorMessage = null;
    });

    try {
      await widget.onDelete();
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _errorMessage = error is ProjectDeletionException
            ? error.userMessage
            : 'No se pudo eliminar el proyecto. El documento principal se conservó. Error: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final confirmed = _confirmation == 'CONFIRMAR';
    return AlertDialog(
      title: const Text('Eliminar proyecto definitivamente'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'La eliminación de “${widget.projectTitle}” sería irreversible.',
          ),
          const SizedBox(height: 12),
          const Text('Escribe CONFIRMAR para validar la intención.'),
          const SizedBox(height: 8),
          TextField(
            enabled: !_deleting,
            onChanged: (value) => setState(() => _confirmation = value),
            decoration: const InputDecoration(labelText: 'CONFIRMAR'),
          ),
          const SizedBox(height: 12),
          Text(
            confirmed
                ? 'Confirmación correcta. Se eliminarán primero los archivos, después sus metadatos y comentarios, y finalmente el proyecto.'
                : 'La palabra debe coincidir exactamente.',
            style: TextStyle(
              color: confirmed
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _deleting ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: confirmed && !_deleting ? _delete : null,
          child: _deleting
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('Eliminando...'),
                  ],
                )
              : const Text('Eliminar definitivamente'),
        ),
      ],
    );
  }
}
