import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/user_model.dart';
import '../../services/community_service.dart';
import '../../widgets/content_detail_sheet.dart';

class AgendaScreen extends StatelessWidget {
  const AgendaScreen({super.key, required this.user});
  final AppUser user;

  Future<void> _create(BuildContext context) async {
    var title = '';
    var location = '';
    var description = '';
    var date = DateTime.now().add(const Duration(days: 1));
    final save = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
                    title: const Text('Nueva reunión o actividad'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          onChanged: (value) => title = value,
                          decoration:
                              const InputDecoration(labelText: 'Título')),
                      const SizedBox(height: 10),
                      TextField(
                          onChanged: (value) => location = value,
                          decoration:
                              const InputDecoration(labelText: 'Lugar')),
                      const SizedBox(height: 10),
                      TextField(
                          onChanged: (value) => description = value,
                          minLines: 2,
                          maxLines: 4,
                          decoration:
                              const InputDecoration(labelText: 'Descripción')),
                      const SizedBox(height: 10),
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.calendar_month),
                          title:
                              Text(DateFormat('dd/MM/yyyy HH:mm').format(date)),
                          onTap: () async {
                            final selectedDate = await showDatePicker(
                                context: context,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 730)),
                                initialDate: date);
                            if (selectedDate == null || !context.mounted) {
                              return;
                            }
                            final selectedTime = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.fromDateTime(date));
                            if (selectedTime != null) {
                              setDialogState(() => date = DateTime(
                                  selectedDate.year,
                                  selectedDate.month,
                                  selectedDate.day,
                                  selectedTime.hour,
                                  selectedTime.minute));
                            }
                          })
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancelar')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Crear'))
                    ])));
    if (save == true && title.trim().isNotEmpty) {
      await CommunityService.instance.createEvent({
        'title': title.trim(),
        'location': location.trim(),
        'description': description.trim(),
        'eventDate': Timestamp.fromDate(date)
      });
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
            return const Center(child: Text('No se pudo cargar la agenda.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          return ListView(
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 90),
              children: [
                Text('Agenda comunitaria',
                    style: Theme.of(context).textTheme.headlineMedium),
                const Text(
                    'Reuniones, eventos, fotografías, comentarios y actas.'),
                const SizedBox(height: 16),
                if (docs.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(
                          child: Text('No hay actividades programadas.')))
                else
                  ...docs.map((document) {
                    final data = document.data();
                    final date = (data['eventDate'] as Timestamp?)?.toDate();

                    return Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          showDragHandle: true,
                          builder: (_) => ContentDetailSheet(
                            collection: 'events',
                            documentId: document.id,
                            title: data['title'] as String? ?? 'Actividad',
                            user: user,
                            allowMinutes: true,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 62,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      date == null
                                          ? '--'
                                          : DateFormat('dd').format(date),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge,
                                    ),
                                    Text(
                                      date == null
                                          ? ''
                                          : DateFormat('MMM', 'es')
                                              .format(date),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      data['title'] as String? ?? 'Actividad',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${date == null ? '' : DateFormat('HH:mm').format(date)} · ${data['location'] as String? ?? ''}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      data['description'] as String? ?? '',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (user.isAdmin)
                                PopupMenuButton<String>(
                                  tooltip: 'Opciones',
                                  onSelected: (value) {
                                    if (value == 'delete') {
                                      _deleteEvent(
                                        context,
                                        document.id,
                                        data['title'] as String? ?? 'Actividad',
                                      );
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem<String>(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete_outline),
                                          SizedBox(width: 8),
                                          Text('Eliminar'),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              else
                                const Padding(
                                  padding: EdgeInsets.only(top: 4),
                                  child: Icon(Icons.chevron_right),
                                ),
                            ],
                          ),
                        ),
                      ),
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
                onPressed: () => _create(context),
                icon: const Icon(Icons.add),
                label: const Text('Actividad'))),
    ]);
  }
}
