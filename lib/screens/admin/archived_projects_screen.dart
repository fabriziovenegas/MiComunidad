import '../../widgets/online_action_dialog.dart';
import '../../widgets/permanent_delete_dialog.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/community_service.dart';
import '../../widgets/content_detail_sheet.dart';
import '../../widgets/project_presentation.dart';

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
              return ProjectPreviewCard(
                data: data,
                onOpen: () => _openProject(context, document),
                detailsLabel: 'Ver información',
                detailsIcon: Icons.visibility_outlined,
                actions: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
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
              );
            },
          );
        },
      ),
    );
  }

  void _openProject(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: ProjectVisuals.sheetBackground,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => ContentDetailSheet(
        collection: 'projects',
        documentId: document.id,
        title: data['title'] as String? ?? 'Proyecto',
        data: data,
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
    await showOnlineActionConfirmation(context,
        actionKey: 'archive-project:${document.id}',
        title: 'Restaurar proyecto',
        question:
            '¿Deseas restaurar “${data['title'] as String? ?? 'Proyecto'}”? Volverá a aparecer en la lista normal.',
        confirmLabel: 'Restaurar',
        successMessage: 'Proyecto restaurado.',
        slowMessage:
            'La restauración del proyecto está tardando. Verifica tu conexión.',
        action: () => CommunityService.instance.restoreProject(document.id));
  }

  Future<void> _confirmPermanentDeletion(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final data = document.data();
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PermanentDeleteDialog(
        entity: 'proyecto',
        actionKey: 'delete-project:${document.id}',
        details: (error) => error is ProjectDeletionException
            ? error.userMessage
            : 'No se pudo completar la eliminación. Revisa su estado antes de reintentar.',
        name: data['title'] as String? ?? 'Proyecto',
        onDelete: () => _deleteProject(document.id),
      ),
    );
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
