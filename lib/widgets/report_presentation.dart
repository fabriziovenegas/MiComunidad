import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/user_model.dart';
import '../utils/text_encoding.dart';
import 'current_report_author_name.dart';
import 'expandable_description.dart';

/// Presentation only. Stored states, moderation and permissions stay unchanged.
class ReportVisuals {
  ReportVisuals._();
  static const green = Color(0xFF276749);
  static const sheetBackground = Color(0xFFF1F6EF);
  static const text = Color(0xFF18201C);
  static const secondaryText = Color(0xFF515B55);

  static String? displayStatus(Map<String, dynamic> data) {
    if (!data.containsKey('moderationStatus') && !data.containsKey('status')) {
      return null;
    }
    if (data['moderationStatus'] == null ||
        data['moderationStatus'] == 'pendiente') {
      return 'en_revision';
    }
    if (data['moderationStatus'] == 'rechazado') return 'rechazado';
    final status = data['status'] as String? ?? 'pendiente';
    return status == 'en_revision' ? 'pendiente' : status;
  }

  static String statusLabel(String status) => switch (status) {
        'en_revision' => 'En revisión',
        'pendiente' => 'Por atender',
        'en_proceso' => 'En proceso',
        'resuelto' => 'Resuelto',
        'rechazado' => 'Rechazado',
        _ => status,
      };

  static (Color, Color) statusColors(String status) => switch (status) {
        'pendiente' => (const Color(0xFFFFF3CD), const Color(0xFF795600)),
        'en_proceso' => (const Color(0xFFE4EFFB), const Color(0xFF285A86)),
        'resuelto' => (const Color(0xFFD8EEDD), const Color(0xFF236344)),
        'rechazado' => (const Color(0xFFF9E5E3), const Color(0xFF9F3832)),
        _ => (const Color(0xFFECEFF1), const Color(0xFF455A64)),
      };

  static String? priorityLabel(Object? priority) => switch (priority) {
        'alta' => 'Prioridad alta',
        'media' => 'Prioridad media',
        'baja' => 'Prioridad baja',
        _ => null,
      };

  static Color priorityColor(Object? priority) => switch (priority) {
        'alta' => const Color(0xFFB13A32),
        'media' => const Color(0xFF795600),
        _ => secondaryText,
      };

  static String? categoryLabel(Object? category) => switch (category) {
        'seguridad' => 'Seguridad',
        'obras' => 'Obras',
        'iluminacion' => 'Iluminación',
        'limpieza' => 'Limpieza',
        'otro' => 'Otro',
        _ => null,
      };
}

class ReportStatusBadge extends StatelessWidget {
  const ReportStatusBadge({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = ReportVisuals.statusColors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
          color: background, borderRadius: BorderRadius.circular(12)),
      child: Text(ReportVisuals.statusLabel(status),
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600, color: foreground)),
    );
  }
}

class ReportPriorityLabel extends StatelessWidget {
  const ReportPriorityLabel({super.key, required this.priority});
  final Object? priority;

  @override
  Widget build(BuildContext context) {
    final label = ReportVisuals.priorityLabel(priority);
    if (label == null) return const SizedBox.shrink();
    final color = ReportVisuals.priorityColor(priority);
    // No colored container: priority remains distinct from the state badge.
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.outlined_flag, size: 21, color: color),
      const SizedBox(width: 6),
      Flexible(
          child: Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: color))),
    ]);
  }
}

class ReportPreviewCard extends StatelessWidget {
  const ReportPreviewCard(
      {super.key,
      required this.data,
      required this.status,
      required this.author,
      required this.onOpen,
      this.onEdit});
  final Map<String, dynamic> data;
  final String status;
  final Widget author;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final title = readableText(data['title']).trim();
    final location = readableText(data['location']).trim();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  child: Text(title.isEmpty ? 'Reporte' : title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: ReportVisuals.text))),
              if (onEdit != null) ...[
                const SizedBox(width: 8),
                IconButton(
                    tooltip: 'Editar mi reporte',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined,
                        color: ReportVisuals.secondaryText)),
              ],
            ]),
            const SizedBox(height: 12),
            Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ReportStatusBadge(status: status),
                  ReportPriorityLabel(priority: data['priority'] ?? 'media'),
                ]),
            const SizedBox(height: 16),
            _ReportLine(
                icon: Icons.person_outline,
                child: DefaultTextStyle.merge(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: ReportVisuals.secondaryText),
                    child: author)),
            if (location.isNotEmpty) ...[
              const SizedBox(height: 10),
              _ReportLine(
                  icon: Icons.location_on_outlined,
                  child: Text(location,
                      maxLines: 2, overflow: TextOverflow.ellipsis)),
            ],
          ]),
        ),
      ),
    );
  }
}

class ReportInformation extends StatelessWidget {
  const ReportInformation(
      {super.key, required this.data, this.reportId, this.user});
  final Map<String, dynamic> data;
  final String? reportId;
  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final status = ReportVisuals.displayStatus(data);
    final category = ReportVisuals.categoryLabel(data['category']);
    final priority = ReportVisuals.priorityLabel(data['priority']);
    final description = readableText(data['description']).trim();
    final location = readableText(data['location']).trim();
    final savedName = readableText(data['createdByName']).trim();
    final rawDate = data['createdAt'];
    final date = rawDate is Timestamp
        ? rawDate.toDate()
        : rawDate is DateTime
            ? rawDate
            : null;
    final hasAuthor = reportId?.isNotEmpty == true || savedName.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (status != null || priority != null) ...[
        Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (status != null) ReportStatusBadge(status: status),
              if (priority != null)
                ReportPriorityLabel(priority: data['priority']),
            ]),
        const SizedBox(height: 20),
      ],
      if (category != null) ...[
        _ReportLine(
            icon: data['category'] == 'iluminacion'
                ? Icons.lightbulb_outline
                : Icons.category_outlined,
            child: Text(category)),
        const SizedBox(height: 12),
      ],
      if (hasAuthor) ...[
        _ReportLine(
            icon: Icons.person_outline,
            child: reportId?.isNotEmpty == true
                ? CurrentReportAuthorName(
                    reportId: reportId!,
                    authorId: readableText(data['createdBy']),
                    savedName: savedName,
                    viewer: user,
                    prefix: 'Reportado por ')
                : Text('Reportado por $savedName')),
        const SizedBox(height: 12),
      ],
      if (location.isNotEmpty) ...[
        _ReportLine(icon: Icons.location_on_outlined, child: Text(location)),
        const SizedBox(height: 12),
      ],
      if (date != null) ...[
        _ReportLine(
            icon: Icons.calendar_today_outlined,
            child:
                Text('Registrado el ${DateFormat('dd/MM/yyyy').format(date)}')),
        const SizedBox(height: 12),
      ],
      if (description.isNotEmpty) ...[
        const SizedBox(height: 8),
        ExpandableDescription(
            text: description,
            style:
                Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.45)),
        const SizedBox(height: 24),
      ],
      if (status == 'rechazado') ...[
        Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: const Color(0xFFF9E5E3),
                borderRadius: BorderRadius.circular(12)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Motivo del rechazo',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(readableText(data['moderationReason']).trim().isEmpty
                  ? 'No se indicó un motivo.'
                  : readableText(data['moderationReason'])),
            ])),
        const SizedBox(height: 24),
      ],
    ]);
  }
}

class _ReportLine extends StatelessWidget {
  const _ReportLine({required this.icon, required this.child});
  final IconData icon;
  final Widget child;
  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: ReportVisuals.green),
          const SizedBox(width: 10),
          Expanded(
              child: DefaultTextStyle.merge(
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: ReportVisuals.secondaryText),
                  child: child)),
        ],
      );
}
