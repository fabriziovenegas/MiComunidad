import 'package:flutter/material.dart';

/// Display labels and icons only; stored category values remain unchanged.
class ReportCategoryVisuals {
  ReportCategoryVisuals._();

  static String? label(Object? category) => switch (category) {
        'seguridad' => 'Seguridad',
        'obras' => 'Obras',
        'iluminacion' => 'Iluminación',
        'limpieza' => 'Limpieza',
        'otro' => 'Otro',
        _ => null,
      };

  static IconData icon(Object? category) => switch (category) {
        'seguridad' => Icons.shield_outlined,
        'obras' => Icons.construction_outlined,
        'iluminacion' => Icons.lightbulb_outline,
        'limpieza' => Icons.cleaning_services_outlined,
        _ => Icons.pending_outlined,
      };
}

class ReportCategoryLabel extends StatelessWidget {
  const ReportCategoryLabel({super.key, required this.category});

  final String category;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ReportCategoryVisuals.icon(category),
              size: 22, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Flexible(
              child: Text(ReportCategoryVisuals.label(category) ?? 'Otro')),
        ],
      );
}
