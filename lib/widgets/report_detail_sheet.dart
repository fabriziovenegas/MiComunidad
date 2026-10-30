import 'attachment_information.dart';
import 'private_storage_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/community_service.dart';
import '../utils/text_encoding.dart';
import '../models/user_model.dart';
import 'image_gallery_screen.dart';
import 'report_presentation.dart';
import 'project_presentation.dart' show ProjectPhotosEmptyState;

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
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .82,
      maxChildSize: .96,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          Text(title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700, color: ReportVisuals.text)),
          const SizedBox(height: 20),
          ReportInformation(data: data, reportId: reportId, user: user),
          const SizedBox(height: 8),
          Text('Fotos compartidas',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  color: ReportVisuals.text)),
          const SizedBox(height: 16),
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
            return const ProjectPhotosEmptyState();
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
                      information: {
                        for (final doc in snapshot.data!.docs)
                          (doc.data()['url'] as String? ?? ''):
                              attachmentInformationBuilder('reports', reportId,
                                  'photos', doc.id, doc.data())
                      },
                      initialIndex: index,
                    ),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: PrivateStorageImage(
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
