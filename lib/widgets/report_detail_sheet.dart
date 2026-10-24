import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/community_service.dart';
import '../utils/text_encoding.dart';
import '../models/user_model.dart';
import 'current_report_author_name.dart';
import 'image_gallery_screen.dart';

class ReportDetailSheet extends StatelessWidget {
  const ReportDetailSheet({
    super.key,
    required this.reportId,
    required this.data,
    this.user,
    this.footer,
  });

  final String reportId;
  final Map<String, dynamic> data;
  final AppUser? user;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final title = _text(data['title'], fallback: 'Reporte');
    final description = _text(
      data['description'],
      fallback: 'Sin descripción.',
    );
    final location = _text(data['location'], fallback: 'No especificada');
    final category = _label(data['category'], fallback: 'No especificada');
    final priority = _label(data['priority'], fallback: 'No especificada');
    final author = _text(data['createdByName'], fallback: 'Vecino');
    final rejected = data['moderationStatus'] == 'rechazado' ||
        data['status'] == 'rechazado';
    final rejectionReason = _text(
      data['moderationReason'],
      fallback: 'No se indicó un motivo.',
    );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .82,
      maxChildSize: .96,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 18),
          _DetailField(
            icon: Icons.description_outlined,
            label: 'Descripción',
            value: description,
          ),
          _DetailField(
            icon: Icons.location_on_outlined,
            label: 'Ubicación',
            value: location,
          ),
          _DetailField(
            icon: Icons.category_outlined,
            label: 'Categoría',
            value: category,
          ),
          _DetailField(
            icon: Icons.priority_high,
            label: 'Prioridad',
            value: priority,
          ),
          _DetailField(
            icon: Icons.person_outline,
            label: 'Reportado por',
            value: author,
            content: CurrentReportAuthorName(
              reportId: reportId,
              authorId: _text(data['createdBy'], fallback: ''),
              savedName: author,
              viewer: user,
            ),
          ),
          if (rejected)
            _DetailField(
              icon: Icons.cancel_outlined,
              label: 'Motivo del rechazo',
              value: rejectionReason,
            ),
          const SizedBox(height: 8),
          Text('Fotografías', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          _ReportPhotos(reportId: reportId),
          if (footer != null) ...[
            const SizedBox(height: 24),
            footer!,
          ],
        ],
      ),
    );
  }

  static String _text(Object? value, {required String fallback}) {
    final text = readableText(value).trim();
    return text.isEmpty ? fallback : text;
  }

  static String _label(Object? value, {required String fallback}) {
    final text = readableText(value).trim();
    if (text.isEmpty) return fallback;
    return text
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({
    required this.icon,
    required this.label,
    required this.value,
    this.content,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? content;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 21, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 3),
                  content ?? Text(value),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ReportPhotos extends StatelessWidget {
  const _ReportPhotos({required this.reportId});

  final String reportId;

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: CommunityService.instance.attachments(
          'reports',
          reportId,
          'photos',
        ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text('No se pudieron cargar las fotografías.');
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final urls = snapshot.data!.docs
              .map((document) => document.data()['url'] as String? ?? '')
              .where((url) => url.isNotEmpty)
              .toList();

          if (urls.isEmpty) {
            return const Text('Este reporte no tiene fotografías adjuntas.');
          }

          return SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: urls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) => InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ImageGalleryScreen(
                      urls: urls,
                      initialIndex: index,
                    ),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    urls[index],
                    width: 132,
                    height: 132,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 132,
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
}
