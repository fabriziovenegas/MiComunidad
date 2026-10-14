import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../models/report_edit.dart';
import '../../services/community_service.dart';
import '../../services/file_service.dart';
import '../../widgets/content_detail_sheet.dart';
import '../../widgets/report_detail_sheet.dart';
import '../../widgets/report_edit_dialog.dart';
import '../../widgets/report_status_dialog.dart';
import '../../utils/text_encoding.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.user});
  final AppUser user;
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  static const _ownReportReadEnabled = true;
  static const _ownReportEditEnabled = true;
  static const _permanentReportDeletionEnabled = true;
  String _filter = 'todos';
  String? _deletingReportId;
  String? _changingStatusReportId;

  Future<void> _createReport() async {
    final formKey = GlobalKey<FormState>();
    var title = '';
    var description = '';
    var location = '';
    var category = 'obras';
    var priority = 'media';
    SelectedUpload? image;
    final save = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
                    title: const Text('Nuevo reporte'),
                    content: SingleChildScrollView(
                        child: Form(
                            key: formKey,
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextFormField(
                                      onChanged: (value) => title = value,
                                      decoration: const InputDecoration(
                                          labelText: 'Título *'),
                                      validator: (value) =>
                                          value == null || value.trim().isEmpty
                                              ? 'El título es obligatorio.'
                                              : null),
                                  const SizedBox(height: 10),
                                  TextFormField(
                                      onChanged: (value) => description = value,
                                      minLines: 3,
                                      maxLines: 5,
                                      decoration: const InputDecoration(
                                          labelText: 'Descripción *'),
                                      validator: (value) =>
                                          value == null || value.trim().isEmpty
                                              ? 'La descripción es obligatoria.'
                                              : null),
                                  const SizedBox(height: 10),
                                  TextField(
                                      onChanged: (value) => location = value,
                                      decoration: const InputDecoration(
                                          labelText: 'Ubicación (opcional)')),
                                  const SizedBox(height: 10),
                                  DropdownButtonFormField<String>(
                                      initialValue: category,
                                      decoration: const InputDecoration(
                                          labelText: 'Categoría'),
                                      items: const [
                                        'seguridad',
                                        'obras',
                                        'iluminacion',
                                        'limpieza',
                                        'otro'
                                      ]
                                          .map((value) => DropdownMenuItem(
                                              value: value,
                                              child: Text(switch (value) {
                                                'seguridad' => 'Seguridad',
                                                'obras' => 'Obras',
                                                'iluminacion' => 'Iluminación',
                                                'limpieza' => 'Limpieza',
                                                _ => 'Otro',
                                              })))
                                          .toList(),
                                      onChanged: (value) => setDialogState(
                                          () => category = value!)),
                                  const SizedBox(height: 10),
                                  DropdownButtonFormField<String>(
                                      initialValue: priority,
                                      decoration: const InputDecoration(
                                          labelText: 'Prioridad'),
                                      items: const ['baja', 'media', 'alta']
                                          .map((value) => DropdownMenuItem(
                                              value: value,
                                              child: Text(switch (value) {
                                                'baja' => 'Baja',
                                                'alta' => 'Alta',
                                                _ => 'Media',
                                              })))
                                          .toList(),
                                      onChanged: (value) => setDialogState(
                                          () => priority = value!)),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                      onPressed: () async {
                                        final selected =
                                            await FileService.pickImage();
                                        if (selected != null) {
                                          setDialogState(
                                              () => image = selected);
                                        }
                                      },
                                      icon:
                                          const Icon(Icons.add_photo_alternate),
                                      label: Text(image?.name ??
                                          'Adjuntar JPG/PNG (opcional)')),
                                  const SizedBox(height: 8),
                                  const Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text('* Campos obligatorios'),
                                  ),
                                ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancelar')),
                      FilledButton(
                          onPressed: () {
                            if (formKey.currentState?.validate() != true) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Completa todos los campos obligatorios antes de enviar el reporte.',
                                  ),
                                ),
                              );
                              return;
                            }
                            Navigator.pop(context, true);
                          },
                          child: const Text('Enviar a revisión'))
                    ])));
    if (save != true) return;
    final reference = FirebaseFirestore.instance.collection('reports').doc();
    await reference.set({
      'title': title.trim(),
      'description': description.trim(),
      'location': location.trim(),
      'category': category,
      'priority': priority,
      'status': 'pendiente',
      'moderationStatus': 'pendiente',
      'createdBy': widget.user.userId,
      'createdByName': widget.user.nombre,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp()
    });
    if (image != null) {
      final queued = await CommunityService.instance.addAttachment(
          collection: 'reports',
          documentId: reference.id,
          kind: 'photos',
          selected: image!);
      if (queued && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'La imagen quedó guardada y se subirá cuando vuelva la señal.'),
        ));
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'Reporte enviado a revisión.',
        ),
      ));
    }
  }

  Future<void> _moderate(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
    bool approve,
  ) async {
    String? reason;
    if (!approve) {
      String inputReason = '';

      reason = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Rechazar reporte'),
            content: TextField(
              maxLines: 3,
              onChanged: (value) => setDialogState(() => inputReason = value),
              decoration: const InputDecoration(
                labelText: 'Motivo',
                helperText: 'El motivo es obligatorio.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: inputReason.trim().isEmpty
                    ? null
                    : () => Navigator.pop(
                          dialogContext,
                          inputReason.trim(),
                        ),
                child: const Text('Rechazar'),
              ),
            ],
          ),
        ),
      );
      if (reason == null) return;
    }
    await CommunityService.instance.moderateReport(
      reportId: document.id,
      approve: approve,
      reason: reason,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(approve ? 'Reporte aprobado.' : 'Reporte rechazado.'),
    ));
  }

  Future<String?> _changeStatus(
      QueryDocumentSnapshot<Map<String, dynamic>> document) async {
    if (_changingStatusReportId != null ||
        !canAdminChangeReportStatus(widget.user, document.data())) {
      return null;
    }
    _changingStatusReportId = document.id;
    try {
      // A dialog can remain open after another status change. Do not reuse its
      // original snapshot when reopening the status selector.
      final current = await document.reference.get();
      final currentData = current.data();
      if (!mounted) return null;
      if (currentData == null ||
          !canAdminChangeReportStatus(widget.user, currentData)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Este reporte ya no permite actualizar su estado.')));
        return null;
      }
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ReportStatusDialog(
          initialStatus: currentData['status'] as String? ?? 'pendiente',
          onSave: (status) => CommunityService.instance
              .updateReport(document.id, {'status': status}),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo cargar el estado actual del reporte.')));
      }
      return null;
    } finally {
      _changingStatusReportId = null;
    }
  }

  static String _label(String value) => switch (value) {
        'en_revision' => 'En Revisión',
        'pendiente' => 'Por Atender',
        'en_proceso' => 'En Proceso',
        'resuelto' => 'Resuelto',
        'rechazado' => 'Rechazado',
        'historial' => 'Historial',
        'alta' => 'Alta',
        'media' => 'Media',
        'baja' => 'Baja',
        _ => value
      };

  static String _displayStatus(Map<String, dynamic> data) {
    if (data['moderationStatus'] == null ||
        data['moderationStatus'] == 'pendiente') {
      return 'en_revision';
    }
    if (data['moderationStatus'] == 'rechazado') return 'rechazado';
    final status = data['status'] as String? ?? 'pendiente';
    return status == 'en_revision' ? 'pendiente' : status;
  }

  bool _canEditContent(Map<String, dynamic> data) {
    return canUserEditReportContent(
      widget.user,
      data,
      FirebaseAuth.instance.currentUser?.uid,
    );
  }

  bool _canManageReport(Map<String, dynamic> data) => canUserManageReport(
        widget.user,
        data,
        FirebaseAuth.instance.currentUser?.uid,
      );

  Future<void> _showReportActions(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
    Map<String, dynamic> data,
  ) async {
    if (!_ownReportEditEnabled || !_canManageReport(data)) return;
    if (reportUsesStatusOnlyDialog(
        widget.user, data, FirebaseAuth.instance.currentUser?.uid)) {
      await _changeStatus(document);
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReportEditDialog(
        data: data,
        allowResolvedContentEditing: widget.user.isAdmin,
        onChangeStatus: canAdminChangeReportStatus(widget.user, data)
            ? () => _changeStatus(document)
            : null,
        onSave: isApprovedReportAuthor(
                widget.user, data, FirebaseAuth.instance.currentUser?.uid)
            ? (draft) => CommunityService.instance.updateOwnReportContent(
                  data['documentId'] as String,
                  draft,
                )
            : null,
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cambios guardados correctamente.')),
      );
    }
  }

  Future<void> _openReportDetails(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
    Map<String, dynamic> data,
  ) async {
    final status = _displayStatus(data);
    final canDeletePermanently = _permanentReportDeletionEnabled &&
        widget.user.isAdmin &&
        _filter == 'historial' &&
        (status == 'resuelto' || status == 'rechazado');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final canChangeStatus = canAdminChangeReportStatus(widget.user, data);
        final footer = canChangeStatus || canDeletePermanently
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canChangeStatus)
                    OutlinedButton.icon(
                      onPressed: () => _changeStatus(document),
                      icon: const Icon(Icons.sync_outlined),
                      label: const Text('Actualizar estado'),
                    ),
                  if (canChangeStatus && canDeletePermanently)
                    const SizedBox(height: 12),
                  if (canDeletePermanently)
                    OutlinedButton.icon(
                      onPressed: _deletingReportId == null
                          ? () => _confirmPermanentReportDeletion(
                                sheetContext,
                                document.id,
                                readableText(data['title']).isEmpty
                                    ? 'Reporte'
                                    : readableText(data['title']),
                              )
                          : null,
                      icon: const Icon(Icons.delete_forever_outlined),
                      label: const Text('Eliminar definitivamente'),
                    ),
                ],
              )
            : null;

        return data['moderationStatus'] != 'aprobado' || status == 'rechazado'
            ? ReportDetailSheet(
                reportId: document.id,
                data: data,
                footer: footer,
              )
            : ContentDetailSheet(
                collection: 'reports',
                documentId: document.id,
                title: data['title'] as String? ?? 'Reporte',
                user: widget.user,
                readOnly: status == 'resuelto',
                allowCommentsWhenReadOnly:
                    canUserCommentOnReport(widget.user, data),
                footer: footer,
              );
      },
    );
  }

  Future<void> _confirmPermanentReportDeletion(
    BuildContext sheetContext,
    String reportId,
    String reportTitle,
  ) async {
    final deleted = await showDialog<bool>(
      context: sheetContext,
      barrierDismissible: false,
      builder: (_) => _PermanentDeleteReportDialog(
        reportTitle: reportTitle,
        onDelete: () => _deleteReport(reportId),
      ),
    );

    if (deleted != true) return;
    if (sheetContext.mounted) Navigator.pop(sheetContext);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reporte eliminado definitivamente.')),
    );
  }

  Future<void> _deleteReport(String reportId) async {
    if (_deletingReportId != null) {
      throw const ReportDeletionException(
        failedStep: 'iniciar la eliminación',
        completedSteps: [],
        cause: 'Ya hay otra eliminación de reporte en curso.',
      );
    }

    setState(() => _deletingReportId = reportId);
    try {
      await CommunityService.instance
          .permanentlyDeleteCompletedReport(reportId);
    } finally {
      if (mounted) setState(() => _deletingReportId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authenticatedUserId = FirebaseAuth.instance.currentUser?.uid;
    return Stack(children: [
      StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        stream: widget.user.isAdmin
            ? CommunityService.instance
                .pendingReports()
                .map((snapshot) => snapshot.docs)
            : CommunityService.instance.reportsVisibleToNeighbor(
                userId: authenticatedUserId ?? '',
                includeOwnReports:
                    _ownReportReadEnabled && authenticatedUserId != null,
              ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
                child: Text('No se pudieron cargar los reportes.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final allDocs = snapshot.data!;
          final pendingDocs = widget.user.isAdmin
              ? allDocs
                  .where((doc) =>
                      doc.data()['moderationStatus'] == null ||
                      doc.data()['moderationStatus'] == 'pendiente')
                  .toList()
              : <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          final docs = allDocs.where((doc) {
            final data = doc.data();
            final moderationStatus = data['moderationStatus'];
            final awaitingModeration =
                moderationStatus == null || moderationStatus == 'pendiente';
            final approved = moderationStatus == 'aprobado';
            final rejected = moderationStatus == 'rechazado';
            final operationalStatus = data['status'] as String? ?? 'pendiente';
            final resolved = approved && operationalStatus == 'resuelto';
            final rejectedAfterApproval =
                approved && operationalStatus == 'rechazado';
            final ownReport = widget.user.isNeighbor &&
                authenticatedUserId != null &&
                data['createdBy'] == authenticatedUserId;

            if (_filter == 'todos') {
              if (widget.user.isAdmin) return !awaitingModeration;
              return approved ||
                  (ownReport && (awaitingModeration || rejected));
            }
            if (_filter == 'en_revision') {
              return awaitingModeration && (widget.user.isAdmin || ownReport);
            }
            if (_filter == 'historial') {
              return resolved ||
                  rejectedAfterApproval ||
                  (rejected && (widget.user.isAdmin || ownReport));
            }
            return approved && _displayStatus(data) == _filter;
          }).toList();
          final showPending = widget.user.isAdmin &&
              pendingDocs.isNotEmpty &&
              _filter == 'todos';
          return ListView(
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 90),
              children: [
                Text('Reportes vecinales',
                    style: Theme.of(context).textTheme.headlineMedium),
                const Text('Registra incidencias y sigue su atención.'),
                const SizedBox(height: 14),
                if (showPending) ...[
                  _PendingReports(
                    reports: pendingDocs,
                    onModerate: _moderate,
                  ),
                  const SizedBox(height: 16),
                ],
                Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      'todos',
                      'en_revision',
                      'pendiente',
                      'en_proceso',
                      'historial'
                    ]
                        .map((value) => FilterChip(
                            selected: _filter == value,
                            label: Text(
                                value == 'todos' ? 'Todos' : _label(value)),
                            onSelected: (_) => setState(() => _filter = value)))
                        .toList()),
                const SizedBox(height: 10),
                if (docs.isEmpty && !showPending)
                  const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(
                          child: Text('No hay reportes en este estado.')))
                else
                  ...docs.map((document) {
                    final data = {
                      ...document.data(),
                      'documentId': document.id,
                    };
                    final status = _displayStatus(data);
                    final moderationReason =
                        readableText(data['moderationReason']).trim();
                    return Card(
                        child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _openReportDetails(document, data),
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Chip(label: Text(_label(status))),
                                        const SizedBox(width: 8),
                                        Chip(
                                            label: Text(_label(
                                                data['priority'] as String? ??
                                                    'media'))),
                                        const Spacer(),
                                        if (_canManageReport(data))
                                          IconButton(
                                              tooltip: _canEditContent(data)
                                                  ? 'Editar mi reporte'
                                                  : 'Actualizar reporte',
                                              onPressed: () =>
                                                  _showReportActions(
                                                      document, data),
                                              icon: const Icon(
                                                  Icons.edit_outlined)),
                                      ]),
                                      Text(
                                          readableText(data['title']).isEmpty
                                              ? 'Reporte'
                                              : readableText(data['title']),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge),
                                      const SizedBox(height: 6),
                                      Text(readableText(data['description']),
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis),
                                      if (status == 'rechazado') ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          'Motivo: ${moderationReason.isEmpty ? 'No se indicó un motivo.' : moderationReason}',
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 10),
                                      Row(children: [
                                        const Icon(Icons.person_outline,
                                            size: 18),
                                        const SizedBox(width: 4),
                                        Expanded(
                                            child: Text(readableText(
                                                        data['createdByName'])
                                                    .isEmpty
                                                ? 'Vecino'
                                                : readableText(
                                                    data['createdByName']))),
                                        const Icon(Icons.location_on_outlined,
                                            size: 18),
                                        const SizedBox(width: 4),
                                        Flexible(
                                            child: Text(
                                                readableText(data['location'])))
                                      ])
                                    ]))));
                  })
              ]);
        },
      ),
      Positioned(
          right: 18,
          bottom: 18,
          child: FloatingActionButton.extended(
              onPressed: _createReport,
              icon: const Icon(Icons.add),
              label: const Text('Reportar'))),
    ]);
  }
}

class _PendingReports extends StatelessWidget {
  const _PendingReports({
    required this.reports,
    required this.onModerate,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> reports;

  final Future<void> Function(
    QueryDocumentSnapshot<Map<String, dynamic>>,
    bool,
  ) onModerate;

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Reportes por aprobar (${reports.length})',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...reports.map((report) {
                final data = report.data();
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => ReportDetailSheet(
                      reportId: report.id,
                      data: data,
                    ),
                  ),
                  title: Text(readableText(data['title'])),
                  subtitle: Text(
                    readableText(data['description']),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Wrap(children: [
                    IconButton(
                      tooltip: 'Rechazar',
                      onPressed: () => onModerate(report, false),
                      icon: const Icon(Icons.close),
                    ),
                    IconButton(
                      tooltip: 'Aprobar',
                      onPressed: () => onModerate(report, true),
                      icon: const Icon(Icons.check_circle_outline),
                    ),
                  ]),
                );
              }),
            ],
          ),
        ),
      );
}

class _PermanentDeleteReportDialog extends StatefulWidget {
  const _PermanentDeleteReportDialog({
    required this.reportTitle,
    required this.onDelete,
  });

  final String reportTitle;
  final Future<void> Function() onDelete;

  @override
  State<_PermanentDeleteReportDialog> createState() =>
      _PermanentDeleteReportDialogState();
}

class _PermanentDeleteReportDialogState
    extends State<_PermanentDeleteReportDialog> {
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
        _errorMessage = error is ReportDeletionException
            ? error.userMessage
            : 'No se pudo eliminar el reporte. El documento principal se conservó. Error: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final confirmed = _confirmation == 'CONFIRMAR';
    return AlertDialog(
      title: const Text('Eliminar reporte definitivamente'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'La eliminación de “${widget.reportTitle}” es irreversible.',
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
                  ? 'Se eliminarán todas las fotografías y los comentarios asociados. Esta acción no se puede deshacer.'
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
