import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../utils/text_encoding.dart';
import 'expandable_description.dart';
import '../models/user_model.dart';
import 'current_content_author_name.dart';

/// Presentation only: attachment kinds, stored dates and permissions stay intact.
class AgendaVisuals {
  AgendaVisuals._();
  static const green = Color(0xFF276749);
  static const dateBackground = Color(0xFFA8F0C5);
  static const sheetBackground = Color(0xFFF1F6EF);
  static const text = Color(0xFF18201C);
  static const secondaryText = Color(0xFF515B55);

  static DateTime? date(Object? value) => value is Timestamp
      ? value.toDate()
      : value is DateTime
          ? value
          : null;
}

class AgendaPreviewCard extends StatelessWidget {
  const AgendaPreviewCard(
      {super.key,
      required this.data,
      required this.onOpen,
      this.onDelete,
      this.onEdit});
  final Map<String, dynamic> data;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final date = AgendaVisuals.date(data['eventDate']);
    final title = readableText(data['title']).trim();
    final location = readableText(data['location']).trim();
    final titleWidget = Text(title.isEmpty ? 'Actividad' : title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(color: AgendaVisuals.text, fontWeight: FontWeight.w700));
    final trailing = onDelete == null && onEdit == null
        ? const Icon(Icons.chevron_right, color: AgendaVisuals.secondaryText)
        : PopupMenuButton<String>(
            tooltip: 'Opciones',
            onSelected: (value) {
              if (value == 'edit') onEdit?.call();
              if (value == 'delete') onDelete?.call();
            },
            itemBuilder: (_) => [
              if (onEdit != null)
                const PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit_outlined),
                      SizedBox(width: 8),
                      Flexible(child: Text('Editar actividad'))
                    ])),
              if (onDelete != null)
                const PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline),
                      SizedBox(width: 8),
                      Flexible(child: Text('Eliminar'))
                    ]))
            ],
          );
    final metadata =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (date != null) ...[
        const SizedBox(height: 8),
        _AgendaLine(
            icon: Icons.access_time,
            label: 'Hora',
            compact: true,
            child: Text(DateFormat('HH:mm').format(date))),
      ],
      if (location.isNotEmpty) ...[
        const SizedBox(height: 8),
        _AgendaLine(
            icon: Icons.location_on_outlined,
            label: 'Ubicación',
            compact: true,
            child:
                Text(location, maxLines: 2, overflow: TextOverflow.ellipsis)),
      ],
    ]);
    return Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(builder: (context, constraints) {
              final largeText = constraints.maxWidth /
                      MediaQuery.textScalerOf(context).scale(1) <
                  230;
              if (largeText) {
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        _AgendaDateBadge(date: date),
                        const Spacer(),
                        trailing
                      ]),
                      const SizedBox(height: 12),
                      titleWidget,
                      metadata,
                    ]);
              }
              return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AgendaDateBadge(date: date),
                    const SizedBox(width: 16),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [titleWidget, metadata])),
                    const SizedBox(width: 4),
                    trailing,
                  ]);
            }),
          ),
        ));
  }
}

class _AgendaDateBadge extends StatelessWidget {
  const _AgendaDateBadge({required this.date});
  final DateTime? date;
  @override
  Widget build(BuildContext context) => Semantics(
        label: date == null
            ? 'Fecha no disponible'
            : DateFormat('d MMMM yyyy', 'es').format(date!),
        excludeSemantics: true,
        child: Container(
          width: 64 +
              20 * (MediaQuery.textScalerOf(context).scale(1).clamp(1, 2) - 1),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
              color: AgendaVisuals.dateBackground,
              borderRadius: BorderRadius.circular(12)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(date == null ? '—' : DateFormat('d').format(date!),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AgendaVisuals.text, fontWeight: FontWeight.w700)),
            if (date != null) ...[
              const SizedBox(height: 3),
              Text(DateFormat('MMM', 'es').format(date!),
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AgendaVisuals.green)),
            ],
          ]),
        ),
      );
}

class AgendaInformation extends StatelessWidget {
  const AgendaInformation(
      {super.key, required this.data, this.eventId, this.user});
  final Map<String, dynamic> data;
  final String? eventId;
  final AppUser? user;
  @override
  Widget build(BuildContext context) {
    final date = AgendaVisuals.date(data['eventDate']);
    final location = readableText(data['location']).trim();
    final description = readableText(data['description']).trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (date != null) ...[
        _AgendaLine(
            icon: Icons.calendar_today_outlined,
            label: 'Fecha y hora',
            child: Text(DateFormat('dd/MM/yyyy • HH:mm').format(date))),
        const SizedBox(height: 12),
      ],
      if (location.isNotEmpty) ...[
        _AgendaLine(
            icon: Icons.location_on_outlined,
            label: 'Ubicación',
            child: Text(location)),
        const SizedBox(height: 12),
      ],
      if (eventId?.isNotEmpty == true) ...[
        ContentCreatorLine(
            collection: 'events', contentId: eventId!, data: data, user: user),
        const SizedBox(height: 12),
      ],
      if (description.isNotEmpty) ...[
        const SizedBox(height: 8),
        ExpandableDescription(
            heading: 'Descripción',
            text: description,
            style:
                Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.45)),
        const SizedBox(height: 24),
      ],
    ]);
  }
}

class AgendaDocumentTile extends StatelessWidget {
  const AgendaDocumentTile(
      {super.key,
      required this.name,
      required this.isPdf,
      required this.onOpen,
      this.onDelete,
      this.onInfo});
  final String name;
  final bool isPdf;
  final VoidCallback onOpen;
  final VoidCallback? onDelete, onInfo;
  @override
  Widget build(BuildContext context) {
    final filename = name.trim().isEmpty
        ? (isPdf ? 'Documento PDF' : 'Imagen adjunta')
        : name;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFCCD7CF))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(children: [
            Icon(isPdf ? Icons.picture_as_pdf : Icons.image_outlined,
                size: 30,
                color: isPdf ? const Color(0xFFB13A32) : AgendaVisuals.green),
            const SizedBox(width: 12),
            Expanded(
                child: Tooltip(
                    message: filename,
                    child: Text(filename,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge))),
            if (onInfo != null)
              IconButton(
                  tooltip: 'Información del archivo',
                  onPressed: onInfo,
                  icon: const Icon(Icons.info_outline)),
            if (onDelete != null) ...[
              const SizedBox(width: 8),
              IconButton.filledTonal(
                  tooltip: 'Eliminar archivo',
                  onPressed: onDelete,
                  style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFE2F0E6),
                      foregroundColor: AgendaVisuals.green),
                  icon: const Icon(Icons.delete_outline)),
            ],
          ]),
        ),
      ),
    );
  }
}

class _AgendaLine extends StatelessWidget {
  const _AgendaLine(
      {required this.icon,
      required this.label,
      required this.child,
      this.compact = false});
  final IconData icon;
  final String label;
  final Widget child;
  final bool compact;
  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: compact ? 20 : 22,
              color: AgendaVisuals.green,
              semanticLabel: label),
          const SizedBox(width: 8),
          Expanded(
              child: DefaultTextStyle.merge(
                  style: (compact
                          ? Theme.of(context).textTheme.bodyMedium
                          : Theme.of(context).textTheme.bodyLarge)
                      ?.copyWith(color: AgendaVisuals.secondaryText),
                  child: child)),
        ],
      );
}
