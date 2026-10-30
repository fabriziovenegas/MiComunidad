import '../models/project_dates.dart';
import 'project_dates_fields.dart';
import 'package:flutter/material.dart';
import '../utils/text_encoding.dart';
import 'expandable_description.dart';
import '../models/user_model.dart';
import 'current_content_author_name.dart';

/// Project-only presentation. These widgets never read or change stored records.
class ProjectVisuals {
  ProjectVisuals._();
  static const green = Color(0xFF276749);
  static const softGreen = Color(0xFFD7EBDC);
  static const sheetBackground = Color(0xFFF1F6EF);
  static const text = Color(0xFF18201C);
  static const secondaryText = Color(0xFF515B55);

  static String? statusLabel(Object? status) => switch (status) {
        'pendiente' => 'Pendiente',
        'en_proceso' => 'En proceso',
        'finalizado' => 'Finalizado',
        _ => null,
      };

  static double? progress(Object? value) =>
      value is num && value.isFinite ? value.clamp(0, 100).toDouble() : null;
}

class ProjectStatusBadge extends StatelessWidget {
  const ProjectStatusBadge(
      {super.key, required this.label, this.outlined = false});
  final String label;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (label) {
      'En proceso' => (const Color(0xFFFFF3CD), const Color(0xFF795600)),
      'Finalizado' => (const Color(0xFFD8EEDD), const Color(0xFF236344)),
      _ => (const Color(0xFFECEFF1), const Color(0xFF455A64)),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: outlined ? 9 : 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(outlined ? 9 : 24),
        border: outlined
            ? Border.all(color: Theme.of(context).colorScheme.outlineVariant)
            : null,
      ),
      child: Text(label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: foreground,
                fontWeight: outlined ? FontWeight.w400 : FontWeight.w600,
              )),
    );
  }
}

class ProjectPreviewCard extends StatelessWidget {
  const ProjectPreviewCard({
    super.key,
    required this.data,
    required this.onOpen,
    this.onEdit,
    this.detailsLabel = 'Fotos y comentarios',
    this.detailsIcon = Icons.photo_camera_outlined,
    this.actions,
  });
  final Map<String, dynamic> data;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;
  final String detailsLabel;
  final IconData detailsIcon;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final title = readableText(data['title']).trim();
    final description = readableText(data['description']).trim();
    final savedLocation = readableText(data['location']).trim();
    final location =
        savedLocation.isEmpty ? 'Ubicación no indicada' : savedLocation;
    final progress = ProjectVisuals.progress(data['progress']);
    final status = ProjectVisuals.statusLabel(data['status']) ?? 'Pendiente';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LayoutBuilder(builder: (context, constraints) {
              final name = Text(title.isEmpty ? 'Proyecto' : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: ProjectVisuals.text,
                      ));
              final badge = ProjectStatusBadge(label: status, outlined: true);
              if (constraints.maxWidth /
                      MediaQuery.textScalerOf(context).scale(1) <
                  240) {
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [name, const SizedBox(height: 10), badge]);
              }
              return Row(children: [
                Expanded(child: name),
                const SizedBox(width: 12),
                ConstrainedBox(
                    constraints:
                        BoxConstraints(maxWidth: constraints.maxWidth * .45),
                    child: badge),
              ]);
            }),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: ProjectVisuals.secondaryText)),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 20, color: ProjectVisuals.secondaryText),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(location,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: ProjectVisuals.secondaryText))),
                ],
              )),
              if (progress != null) ...[
                const SizedBox(width: 12),
                Semantics(
                  label: 'Avance del proyecto: ${progress.round()} por ciento',
                  excludeSemantics: true,
                  child: Text('${progress.round()} %',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: ProjectVisuals.green,
                          )),
                ),
              ],
            ]),
            const SizedBox(height: 12),
            Divider(
                height: 1,
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withAlpha(140)),
            ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(children: [
                  Icon(detailsIcon,
                      size: 20, color: ProjectVisuals.secondaryText),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(detailsLabel,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: ProjectVisuals.secondaryText))),
                  if (onEdit != null)
                    IconButton(
                      tooltip: 'Editar proyecto',
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit,
                          color: ProjectVisuals.secondaryText),
                    ),
                ])),
            if (actions != null) ...[actions!, const SizedBox(height: 10)],
          ]),
        ),
      ),
    );
  }
}

class ProjectInformation extends StatelessWidget {
  const ProjectInformation(
      {super.key, required this.data, this.projectId, this.user});
  final Map<String, dynamic> data;
  final String? projectId;
  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final status = ProjectVisuals.statusLabel(data['status']);
    final progress = ProjectVisuals.progress(data['progress']);
    final location = readableText(data['location']).trim();
    final description = readableText(data['description']).trim();
    final hasCreator = projectId?.isNotEmpty == true;
    if (status == null &&
        progress == null &&
        location.isEmpty &&
        description.isEmpty &&
        !hasCreator &&
        ProjectDates.date(data['startDate']) == null &&
        ProjectDates.date(data['expectedEndDate']) == null) {
      return const SizedBox.shrink();
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (status != null || progress != null) ...[
        SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                if (status != null) ProjectStatusBadge(label: status),
                if (progress != null)
                  Text('${progress.round()} % de avance',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: ProjectVisuals.secondaryText)),
              ],
            )),
        if (progress != null) ...[
          const SizedBox(height: 10),
          ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress / 100,
                minHeight: 9,
                color: ProjectVisuals.green,
                backgroundColor: ProjectVisuals.softGreen,
                semanticsLabel: 'Avance del proyecto',
                semanticsValue: '${progress.round()} %',
              )),
        ],
        const SizedBox(height: 24),
      ],
      if (location.isNotEmpty) ...[
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.location_on_outlined,
              size: 22,
              color: ProjectVisuals.green,
              semanticLabel: 'Ubicación'),
          const SizedBox(width: 8),
          Expanded(
              child: Text(location,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: ProjectVisuals.secondaryText))),
        ]),
        SizedBox(height: hasCreator ? 12 : 24),
      ],
      if (hasCreator) ...[
        ContentCreatorLine(
            collection: 'projects',
            contentId: projectId!,
            data: data,
            user: user),
        const SizedBox(height: 24),
      ],
      if (ProjectDates.date(data['startDate']) != null ||
          ProjectDates.date(data['expectedEndDate']) != null) ...[
        ProjectDatesSummary(data: data),
        const SizedBox(height: 24),
      ],
      if (description.isNotEmpty) ...[
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

class ProjectPhotosEmptyState extends StatelessWidget {
  const ProjectPhotosEmptyState({super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: SizedBox(
            width: double.infinity,
            child: Column(children: [
              const Icon(Icons.image_outlined,
                  size: 36, color: Color(0xFF98A09A)),
              const SizedBox(height: 12),
              Text('Aún no hay fotografías.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: ProjectVisuals.secondaryText)),
            ])),
      );
}
