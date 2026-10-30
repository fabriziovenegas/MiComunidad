import '../../widgets/limited_text_form_field.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/user_model.dart';
import '../../services/community_service.dart';
import '../../widgets/content_detail_sheet.dart';
import '../../widgets/agenda_presentation.dart';
import '../../services/pending_content_service.dart';
import '../../services/event_content_editor.dart';
import '../../widgets/pending_content_notice.dart';
import '../../widgets/form_submission_guard.dart';
import '../../widgets/upload_error_notice.dart';

class AgendaScreen extends StatelessWidget {
  const AgendaScreen(
      {super.key, required this.user, this.pendingContent, this.eventEditor});
  final AppUser user;
  final PendingContentService? pendingContent;
  final EventContentEditor? eventEditor;
  PendingContentService get _outbox =>
      pendingContent ?? PendingContentService.instance;

  Future<void> _eventForm(BuildContext context,
      [QueryDocumentSnapshot<Map<String, dynamic>>? document]) async {
    if (!user.isAdmin) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    final formKey = GlobalKey<FormState>();
    final draftId = document == null ? _outbox.newId() : null;
    final data = document?.data() ?? const <String, dynamic>{};
    final storedDate = data['eventDate'];
    var dateChanged = false;
    PendingSendResult? result;
    var title = data['title'] as String? ?? '';
    var location = data['location'] as String? ?? '';
    var description = data['description'] as String? ?? '';
    var date = AgendaVisuals.date(storedDate) ??
        DateTime.now().add(const Duration(days: 1));
    final save = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => FormSubmissionGuard(
                validate: () => formKey.currentState?.validate() == true,
                onSubmit: () async {
                  final fields = <String, dynamic>{
                    'title': title.trim(),
                    'location': location.trim(),
                    'description': description.trim(),
                    'eventDate': !dateChanged && storedDate is Timestamp
                        ? storedDate
                        : Timestamp.fromDate(date),
                  };
                  if (document != null) {
                    if (eventEditor != null) {
                      await eventEditor!.save(document.id, fields);
                    } else {
                      await CommunityService.instance
                          .updateEvent(document.id, fields);
                    }
                  } else {
                    result = await _outbox.submit(
                        id: draftId!,
                        collection: 'events',
                        expectedUserId: user.userId,
                        fields: fields);
                  }
                },
                onSubmitted: (context) => Navigator.pop(context, true),
                builder: (context, saving, submit) => AlertDialog(
                        title: Text(document == null
                            ? 'Nueva reunión o actividad'
                            : 'Editar actividad'),
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
                                          validator: (value) => value == null ||
                                                  value.trim().isEmpty
                                              ? 'El título es obligatorio.'
                                              : null,
                                          decoration: const InputDecoration(
                                              labelText: 'Título')),
                                      const SizedBox(height: 10),
                                      LimitedTextFormField(
                                          characterLimit: 300,
                                          enabled: !saving,
                                          initialValue: location,
                                          onChanged: (value) =>
                                              location = value,
                                          decoration: const InputDecoration(
                                              labelText: 'Lugar')),
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
                                              labelText: 'Descripción')),
                                      const SizedBox(height: 10),
                                      ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading:
                                              const Icon(Icons.calendar_month),
                                          title: Text(
                                              DateFormat('dd/MM/yyyy HH:mm')
                                                  .format(date)),
                                          onTap: saving
                                              ? null
                                              : () async {
                                                  final selectedDate = await showDatePicker(
                                                      context: context,
                                                      firstDate: document ==
                                                              null
                                                          ? DateTime.now()
                                                          : DateTime(
                                                              date.year < 2000
                                                                  ? date.year
                                                                  : 2000),
                                                      lastDate: date.isAfter(
                                                              DateTime.now().add(
                                                                  const Duration(
                                                                      days:
                                                                          730)))
                                                          ? date
                                                          : DateTime.now().add(
                                                              const Duration(
                                                                  days: 730)),
                                                      initialDate: date);
                                                  if (selectedDate == null ||
                                                      !context.mounted) {
                                                    return;
                                                  }
                                                  final selectedTime =
                                                      await showTimePicker(
                                                          context: context,
                                                          initialTime: TimeOfDay
                                                              .fromDateTime(
                                                                  date));
                                                  if (selectedTime != null) {
                                                    setDialogState(() {
                                                      dateChanged = true;
                                                      date = DateTime(
                                                          selectedDate.year,
                                                          selectedDate.month,
                                                          selectedDate.day,
                                                          selectedTime.hour,
                                                          selectedTime.minute);
                                                    });
                                                  }
                                                })
                                    ]))),
                        actions: [
                          TextButton(
                              onPressed: saving
                                  ? null
                                  : () => Navigator.pop(context, false),
                              child: const Text('Cancelar')),
                          FilledButton(
                              onPressed: saving ? null : submit,
                              child: Text(saving
                                  ? 'Guardando…'
                                  : document == null
                                      ? 'Crear'
                                      : 'Guardar cambios'))
                        ]))));
    if (save == true && context.mounted) {
      if (document != null) {
        showSuccessNotice(context, 'Actividad actualizada.');
        return;
      }
      if (result?.state == PendingSendState.blocked) {
        showUploadError(context,
            'Actividad guardada en este dispositivo. ${result!.reason} Revisa los pendientes.');
      } else {
        showSuccessNotice(
            context,
            result?.state == PendingSendState.queued
                ? 'Actividad guardada en este dispositivo. Se enviará cuando haya conexión.'
                : 'Actividad creada.');
      }
    }
  }

  Future<void> _deleteEvent(
    BuildContext context,
    String eventId,
    String eventTitle,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar actividad'),
        content: Text(
          '¿Deseas eliminar "$eventTitle"? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await CommunityService.instance.deleteEvent(eventId);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Actividad eliminada.'),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo eliminar la actividad: $error'),
            action: SnackBarAction(
              label: 'Reintentar',
              onPressed: () => _deleteEvent(context, eventId, eventTitle),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: CommunityService.instance.events(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ListView(children: [
              PendingCollectionNotice(
                  userId: user.userId, collection: 'events', service: _outbox),
              const Text('No se pudo cargar la agenda.')
            ]);
          }
          if (!snapshot.hasData) {
            return Column(children: [
              PendingCollectionNotice(
                  userId: user.userId, collection: 'events', service: _outbox),
              const Expanded(child: Center(child: CircularProgressIndicator()))
            ]);
          }
          final docs = snapshot.data!.docs;
          return ListView(
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 90),
              children: [
                Text('Agenda comunitaria',
                    style: Theme.of(context).textTheme.headlineMedium),
                const Text(
                    'Reuniones, eventos, fotografías, comentarios y actas.'),
                PendingCollectionNotice(
                    userId: user.userId,
                    collection: 'events',
                    service: _outbox),
                const SizedBox(height: 16),
                if (docs.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(
                          child: Text('No hay actividades programadas.')))
                else
                  ...docs.map((document) {
                    final data = document.data();
                    return AgendaPreviewCard(
                      data: data,
                      onEdit: user.isAdmin
                          ? () => _eventForm(context, document)
                          : null,
                      onOpen: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        backgroundColor: AgendaVisuals.sheetBackground,
                        shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                                top: Radius.circular(28))),
                        builder: (_) => ContentDetailSheet(
                          collection: 'events',
                          documentId: document.id,
                          title: data['title'] as String? ?? 'Actividad',
                          data: data,
                          user: user,
                          allowMinutes: true,
                        ),
                      ),
                      onDelete: user.isAdmin
                          ? () => _deleteEvent(context, document.id,
                              data['title'] as String? ?? 'Actividad')
                          : null,
                    );
                  })
              ]);
        },
      ),
      if (user.isAdmin)
        Positioned(
            right: 18,
            bottom: 18,
            child: FloatingActionButton.extended(
                onPressed: () => _eventForm(context),
                icon: const Icon(Icons.add),
                label: const Text('Actividad'))),
    ]);
  }
}
