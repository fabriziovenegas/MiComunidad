import '../../services/upload_connection.dart';
import '../../widgets/project_dates_fields.dart';
import '../../models/project_dates.dart';
import '../../widgets/limited_text_form_field.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../admin/archived_projects_screen.dart';
import '../../services/community_service.dart';
import '../../widgets/content_detail_sheet.dart';
import '../../utils/project_progress_input.dart';
import '../../services/pending_content_service.dart';
import '../../widgets/pending_content_notice.dart';
import '../../widgets/form_submission_guard.dart';
import '../../widgets/upload_error_notice.dart';
import '../../widgets/project_presentation.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key, required this.user, this.pendingContent});
  final AppUser user;
  final PendingContentService? pendingContent;
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  String _filter = 'todos';
  final Map<String, Map<String, dynamic>> _editDrafts = {};
  PendingContentService get _outbox =>
      widget.pendingContent ?? PendingContentService.instance;

  Future<void> _projectForm(
      [QueryDocumentSnapshot<Map<String, dynamic>>? document]) async {
    if (ModalRoute.of(context)?.isCurrent == false) return;
    final formKey = GlobalKey<FormState>();
    final draftId = document == null ? _outbox.newId() : null;
    PendingSendResult? result;
    final data = document?.data() ?? const <String, dynamic>{};
    final initial = {...data, ...?_editDrafts[document?.id]};
    Map<String, dynamic>? retainedDraft;
    var title = initial['title'] as String? ?? '';
    var location = initial['location'] as String? ?? '';
    var description = initial['description'] as String? ?? '';
    final savedProgress = document == null ? '' : initial['progress'] ?? 0;
    var progress = savedProgress is num &&
            savedProgress.isFinite &&
            savedProgress == savedProgress.roundToDouble()
        ? savedProgress.toStringAsFixed(0)
        : '$savedProgress';
    var status = initial['status'] as String? ?? 'pendiente';
    var startDate = ProjectDates.date(initial['startDate']);
    var endDate = ProjectDates.date(initial['expectedEndDate']);
    final action = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => FormSubmissionGuard(
                slowAfter:
                    document == null ? null : const Duration(seconds: 10),
                errorMessage: (error) => error is FirebaseException &&
                        error.code == 'unavailable'
                    ? 'Necesitas conexión para guardar los cambios'
                    : 'Hubo un problema con el envío. Tus datos se conservan.',
                validate: () => formKey.currentState?.validate() == true,
                onSubmit: () async {
                  final percent = document == null && progress.isEmpty
                      ? 0
                      : ProjectProgressInputFormatter.parse(progress);
                  if (percent == null) throw StateError('Avance no válido.');
                  final payload = <String, dynamic>{
                    'title': title.trim(),
                    'location': location.trim(),
                    'description': description.trim(),
                    'progress': percent,
                    'status': status,
                    if (startDate != null)
                      'startDate': Timestamp.fromDate(startDate!),
                    if (endDate != null)
                      'expectedEndDate': Timestamp.fromDate(endDate!),
                  };
                  if (document == null) {
                    result = await _outbox.submit(
                        id: draftId!,
                        collection: 'projects',
                        expectedUserId: widget.user.userId,
                        fields: payload);
                  } else {
                    if (await UploadConnection.isOffline()) {
                      throw FirebaseException(
                          plugin: 'cloud_firestore', code: 'unavailable');
                    }
                    await CommunityService.instance.updateProject(document.id, {
                      ...payload,
                      if (startDate == null && data.containsKey('startDate'))
                        'startDate': FieldValue.delete(),
                      if (endDate == null &&
                          data.containsKey('expectedEndDate'))
                        'expectedEndDate': FieldValue.delete(),
                    });
                    if (retainedDraft != null &&
                        identical(_editDrafts[document.id], retainedDraft)) {
                      _editDrafts.remove(document.id);
                    }
                    if (!context.mounted && mounted) {
                      showSuccessNotice(this.context, 'Cambios guardados');
                    }
                  }
                },
                onSubmitted: (context) => Navigator.pop(context, 'save'),
                builder: (context, saving, submit) => AlertDialog(
                        title: Text(document == null
                            ? 'Nuevo proyecto'
                            : 'Actualizar proyecto'),
                        content: SingleChildScrollView(
                            child: Form(
                                key: formKey,
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      LimitedTextFormField(
                                          characterLimit: 160,
                                          enabled: !saving,
                                          initialValue: title,
                                          onChanged: (value) => title = value,
                                          decoration: const InputDecoration(
                                              labelText: 'Nombre *'),
                                          validator: (value) => value == null ||
                                                  value.trim().isEmpty
                                              ? 'El nombre es obligatorio.'
                                              : null),
                                      const SizedBox(height: 10),
                                      LimitedTextFormField(
                                          characterLimit: 300,
                                          enabled: !saving,
                                          initialValue: location,
                                          onChanged: (value) =>
                                              location = value,
                                          decoration: const InputDecoration(
                                              labelText: 'Ubicación')),
                                      const SizedBox(height: 10),
                                      LimitedTextFormField(
                                          characterLimit: 4000,
                                          enabled: !saving,
                                          initialValue: description,
                                          onChanged: (value) =>
                                              description = value,
                                          minLines: 2,
                                          maxLines: 4,
                                          decoration: const InputDecoration(
                                              labelText: 'Descripción *'),
                                          validator: (value) => value == null ||
                                                  value.trim().isEmpty
                                              ? 'La descripción es obligatoria.'
                                              : null),
                                      const SizedBox(height: 10),
                                      TextFormField(
                                          enabled: !saving,
                                          initialValue: progress,
                                          onChanged: (value) =>
                                              progress = value,
                                          keyboardType: const TextInputType
                                              .numberWithOptions(
                                              decimal: false, signed: false),
                                          inputFormatters: [
                                            ProjectProgressInputFormatter()
                                          ],
                                          validator: (value) => document ==
                                                      null &&
                                                  (value ?? '').isEmpty
                                              ? null
                                              : ProjectProgressInputFormatter
                                                  .validate(value),
                                          autovalidateMode: AutovalidateMode
                                              .onUserInteraction,
                                          decoration: const InputDecoration(
                                              labelText: 'Avance (%)',
                                              hintText: '0 a 100')),
                                      const SizedBox(height: 10),
                                      DropdownButtonFormField<String>(
                                          initialValue: status,
                                          decoration: const InputDecoration(
                                              labelText: 'Estado'),
                                          items: const [
                                            'pendiente',
                                            'en_proceso',
                                            'finalizado'
                                          ]
                                              .map((value) => DropdownMenuItem(
                                                  value: value,
                                                  child: Text(_label(value))))
                                              .toList(),
                                          onChanged: saving
                                              ? null
                                              : (value) => setDialogState(
                                                  () => status = value!)),
                                      const SizedBox(height: 10),
                                      ProjectDatesFields(
                                          start: startDate,
                                          end: endDate,
                                          enabled: !saving,
                                          onChanged: (start, end) =>
                                              setDialogState(() {
                                                startDate = start;
                                                endDate = end;
                                              })),
                                      const SizedBox(height: 10),
                                      const Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text('* Campos obligatorios'),
                                      ),
                                      if (document != null) ...[
                                        const SizedBox(height: 20),
                                        const Divider(),
                                        const SizedBox(height: 8),
                                        SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton.icon(
                                            onPressed: saving
                                                ? null
                                                : () async {
                                                    final confirmed =
                                                        await showDialog<bool>(
                                                      context: context,
                                                      builder:
                                                          (confirmContext) =>
                                                              AlertDialog(
                                                        title: const Text(
                                                            'Archivar proyecto'),
                                                        content: const Text(
                                                          '¿Deseas archivar este proyecto? '
                                                          'Dejará de aparecer en la lista normal y podrás restaurarlo desde Archivados.',
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                    confirmContext,
                                                                    false),
                                                            child: const Text(
                                                                'Cancelar'),
                                                          ),
                                                          FilledButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                    confirmContext,
                                                                    true),
                                                            child: const Text(
                                                                'Archivar'),
                                                          ),
                                                        ],
                                                      ),
                                                    );

                                                    if (confirmed == true &&
                                                        context.mounted) {
                                                      Navigator.pop(
                                                          context, 'trash');
                                                    }
                                                  },
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Theme.of(context)
                                                  .colorScheme
                                                  .error,
                                              side: BorderSide(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error,
                                              ),
                                            ),
                                            icon: const Icon(
                                                Icons.archive_outlined),
                                            label:
                                                const Text('Archivar proyecto'),
                                          ),
                                        ),
                                      ],
                                    ]))),
                        actions: [
                          TextButton(
                            onPressed: saving &&
                                    !FormSubmissionGuard.isTakingLong(context)
                                ? null
                                : () => Navigator.pop(context, 'cancel'),
                            child: Text(saving &&
                                    FormSubmissionGuard.isTakingLong(context)
                                ? 'Cerrar'
                                : 'Cancelar'),
                          ),
                          FilledButton(
                            onPressed: saving ? null : submit,
                            child: Text(saving
                                ? (FormSubmissionGuard.isTakingLong(context)
                                    ? 'Esperando confirmación…'
                                    : 'Guardando…')
                                : 'Guardar'),
                          ),
                        ]))));
    if (document != null) {
      if (action == 'save' || action == 'trash') {
        _editDrafts.remove(document.id);
      } else {
        // Keep the edit in this screen even if a slow request is still awaiting acknowledgement.
        retainedDraft = {
          'title': title,
          'location': location,
          'description': description,
          'progress': progress,
          'status': status,
          'startDate':
              startDate == null ? null : Timestamp.fromDate(startDate!),
          'expectedEndDate':
              endDate == null ? null : Timestamp.fromDate(endDate!),
        };
        _editDrafts[document.id] = retainedDraft;
      }
    }
    if (action == 'trash' && document != null) {
      try {
        await CommunityService.instance.moveProjectToTrash(
          document.id,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Proyecto archivado.'),
            ),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No se pudo archivar el proyecto: $error'),
            ),
          );
        }
      }

      return;
    }

    if (action == 'save' && mounted) {
      if (result?.state == PendingSendState.blocked) {
        showUploadError(context,
            'Proyecto guardado en este dispositivo. ${result!.reason} Revisa los pendientes.');
      } else {
        showSuccessNotice(
            context,
            result?.state == PendingSendState.queued
                ? 'Proyecto guardado en este dispositivo. Se enviará cuando haya conexión.'
                : document != null
                    ? 'Cambios guardados'
                    : 'Proyecto guardado.');
      }
    }
  }

  void _open(QueryDocumentSnapshot<Map<String, dynamic>> document) {
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
            user: widget.user));
  }

  static String _label(String value) => switch (value) {
        'en_proceso' => 'En proceso',
        'finalizado' => 'Finalizado',
        _ => 'Pendiente'
      };

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: CommunityService.instance.activeProjects(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ListView(children: [
                PendingCollectionNotice(
                    userId: widget.user.userId,
                    collection: 'projects',
                    service: _outbox),
                const Text('No se pudieron cargar los proyectos.')
              ]);
            }
            if (!snapshot.hasData) {
              return Column(children: [
                PendingCollectionNotice(
                    userId: widget.user.userId,
                    collection: 'projects',
                    service: _outbox),
                const Expanded(
                    child: Center(child: CircularProgressIndicator()))
              ]);
            }
            final documents = snapshot.data!.docs
                .where((doc) =>
                    _filter == 'todos' || doc.data()['status'] == _filter)
                .toList()
              ..sort((left, right) {
                final leftDate = left.data()['createdAt'] as Timestamp?;
                final rightDate = right.data()['createdAt'] as Timestamp?;
                return (rightDate?.millisecondsSinceEpoch ?? 0)
                    .compareTo(leftDate?.millisecondsSinceEpoch ?? 0);
              });
            return CustomScrollView(slivers: [
              SliverToBoxAdapter(
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Proyectos comunitarios',
                                style:
                                    Theme.of(context).textTheme.headlineMedium),
                            const Text(
                                'Consulta avances y comparte fotografías o comentarios.'),
                            PendingCollectionNotice(
                                userId: widget.user.userId,
                                collection: 'projects',
                                service: _outbox),
                            const SizedBox(height: 14),
                            ProjectFiltersLayout(
                              archivedButton: widget.user.isAdmin
                                  ? OutlinedButton.icon(
                                      onPressed: () =>
                                          Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              ArchivedProjectsScreen(
                                            user: widget.user,
                                          ),
                                        ),
                                      ),
                                      icon: const Icon(Icons.archive_outlined),
                                      label: const Text('Archivados'),
                                    )
                                  : null,
                              selectedFilter: _filter,
                              onSelected: (value) =>
                                  setState(() => _filter = value),
                            )
                          ]))),
              if (documents.isEmpty)
                const SliverFillRemaining(
                    child: Center(
                        child: Text('No hay proyectos en esta categoría.')))
              else
                SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
                    sliver: SliverList.builder(
                        itemCount: documents.length,
                        itemBuilder: (context, index) {
                          final document = documents[index];
                          final data = document.data();
                          return ProjectPreviewCard(
                            data: data,
                            onOpen: () => _open(document),
                            onEdit: widget.user.isAdmin
                                ? () => _projectForm(document)
                                : null,
                          );
                        })),
            ]);
          },
        ),
        if (widget.user.isAdmin)
          Positioned(
              right: 18,
              bottom: 18,
              child: FloatingActionButton.extended(
                  onPressed: () => _projectForm(),
                  icon: const Icon(Icons.add),
                  label: const Text('Proyecto'))),
      ],
    );
  }
}

/// Layout only; selection and navigation remain owned by ProjectsScreen.
class ProjectFiltersLayout extends StatelessWidget {
  const ProjectFiltersLayout({
    super.key,
    required this.selectedFilter,
    required this.onSelected,
    this.archivedButton,
  });

  final String selectedFilter;
  final ValueChanged<String> onSelected;
  final Widget? archivedButton;

  @override
  Widget build(BuildContext context) {
    Widget filter(String value) => Expanded(
          child: FilterChip(
            selected: selectedFilter == value,
            label: SizedBox(
              // RawChip loosens its outer constraints. An expanding label
              // makes the painted surface fill the column, not just its text.
              width: double.infinity,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 26),
                child: Center(
                  heightFactor: 1,
                  child: Text(value == 'todos'
                      ? 'Todos'
                      : _ProjectsScreenState._label(value)),
                ),
              ),
            ),
            onSelected: (_) => onSelected(value),
          ),
        );

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Filtros',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            if (archivedButton != null) ...[
              const SizedBox(width: 12),
              archivedButton!,
            ],
          ],
        ),
        const SizedBox(height: 12),
        Row(children: [
          filter('todos'),
          const SizedBox(width: 12),
          filter('pendiente'),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          filter('en_proceso'),
          const SizedBox(width: 12),
          filter('finalizado'),
        ]),
      ],
    );
  }
}
