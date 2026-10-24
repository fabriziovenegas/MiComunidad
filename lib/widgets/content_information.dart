import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/text_encoding.dart';

/// A compact reading section; the preview's title and controls stay outside it.
/// Only existing, explicitly selected content fields are displayed.
class ContentInformation extends StatelessWidget {
  const ContentInformation({
    super.key,
    required this.collection,
    required this.data,
  });

  final String collection;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    if (!const ['projects', 'reports', 'events'].contains(collection)) {
      return const SizedBox.shrink();
    }
    final description = readableText(data['description']).trim();
    final location = readableText(data['location']).trim();
    final badges = <String>[];
    if (collection == 'projects') {
      final status = switch (data['status']) {
        'pendiente' => 'Pendiente',
        'en_proceso' => 'En proceso',
        'finalizado' => 'Finalizado',
        _ => null,
      };
      if (status != null) badges.add(status);
      final progress = data['progress'];
      if (progress is num && progress.isFinite) {
        badges.add('${progress.clamp(0, 100).round()} % de avance');
      }
    } else if (collection == 'reports') {
      final status = switch (data['status']) {
        'pendiente' || 'en_revision' => 'Por atender',
        'en_proceso' => 'En proceso',
        'resuelto' => 'Resuelto',
        _ => null,
      };
      final category = switch (data['category']) {
        'seguridad' => 'Seguridad',
        'obras' => 'Obras',
        'iluminacion' => 'Iluminación',
        'limpieza' => 'Limpieza',
        'otro' => 'Otro',
        _ => null,
      };
      final priority = switch (data['priority']) {
        'baja' => 'Prioridad baja',
        'media' => 'Prioridad media',
        'alta' => 'Prioridad alta',
        _ => null,
      };
      badges.addAll([
        if (status != null) status,
        if (category != null) category,
        if (priority != null) priority
      ]);
    }
    final rawDate = data[collection == 'events' ? 'eventDate' : 'createdAt'];
    final date = rawDate is Timestamp
        ? rawDate.toDate()
        : rawDate is DateTime
            ? rawDate
            : null;
    // The agenda needs its full date/time; reports benefit from their register
    // date. Project details already have state/progress, so avoid extra clutter.
    final showDate = date != null && collection != 'projects';
    if (description.isEmpty &&
        location.isEmpty &&
        badges.isEmpty &&
        !showDate) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (badges.isNotEmpty) ...[
          Text(
            badges.join(' • '),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
        ],
        if (description.isNotEmpty) ...[
          Text(description,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(height: 1.45)),
          const SizedBox(height: 16),
        ],
        if (location.isNotEmpty) ...[
          _InformationLine(
              icon: Icons.location_on_outlined,
              label: 'Ubicación',
              value: location),
          if (showDate) const SizedBox(height: 12),
        ],
        if (showDate) ...[
          _InformationLine(
            icon: Icons.calendar_today_outlined,
            label: collection == 'events' ? 'Fecha y hora' : 'Registrado',
            value:
                '${collection == 'events' ? '' : 'Registrado el '}${DateFormat(collection == 'events' ? 'dd/MM/yyyy • HH:mm' : 'dd/MM/yyyy').format(date)}',
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _InformationLine extends StatelessWidget {
  const _InformationLine(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
              semanticLabel: label),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      );
}
