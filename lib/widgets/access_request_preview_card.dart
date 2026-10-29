import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/access_request.dart';

/// Presentation only. The screen supplies its existing open/review actions.
class AccessRequestPreviewCard extends StatelessWidget {
  const AccessRequestPreviewCard({
    super.key,
    required this.request,
    required this.onOpen,
    this.reviewActions,
  });

  final AccessRequest request;
  final VoidCallback onOpen;
  final Widget? reviewActions;

  static const _green = Color(0xFF276749);
  static const _text = Color(0xFF18201C);
  static const _secondary = Color(0xFF657066);
  static const _labels = [
    'Pendiente',
    'Aprobada',
    'Rechazada',
    'Acceso retirado'
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final statusStyle = (theme.textTheme.labelMedium ?? const TextStyle())
        .copyWith(fontSize: 12, fontWeight: FontWeight.w500, height: 1.3);
    final dateStyle = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
        fontSize: 12,
        height: 1.3,
        color: _secondary,
        fontFeatures: const [FontFeature.tabularFigures()]);
    final (label, icon, background, foreground) = switch (request.status) {
      'pendiente' => (
          'Pendiente',
          Icons.hourglass_top_rounded,
          const Color(0xFFFFF3CD),
          const Color(0xFF795600)
        ),
      'aprobado' => (
          'Aprobada',
          Icons.check_circle_outline_rounded,
          const Color(0xFFD8EEDD),
          const Color(0xFF236344)
        ),
      'rechazado' => (
          'Rechazada',
          Icons.cancel_outlined,
          const Color(0xFFFCE4E4),
          const Color(0xFFA52B2B)
        ),
      'retirado' => (
          'Acceso retirado',
          Icons.remove_circle_outline_rounded,
          const Color(0xFFECEFF1),
          const Color(0xFF455A64)
        ),
      _ => (
          request.status,
          Icons.info_outline_rounded,
          const Color(0xFFECEFF1),
          const Color(0xFF455A64)
        ),
    };
    final initials = request.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.characters.first.toUpperCase())
        .join();
    Size measure(String value, TextStyle style,
        {double maxWidth = double.infinity}) {
      final painter = TextPainter(
          text: TextSpan(text: value, style: style),
          textDirection: direction,
          textScaler: scaler)
        ..layout(maxWidth: maxWidth);
      final size = painter.size;
      painter.dispose();
      return size;
    }

    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.outlineVariant)),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: LayoutBuilder(builder: (context, constraints) {
            // Measure the longest supported status, rather than the current
            // label, so every badge has the same dimensions at this text scale.
            final labels = [..._labels, if (!_labels.contains(label)) label];
            const badgeChrome = 24.0 + 16 + 6;
            final naturalWidth = labels
                    .map((s) => measure(s, statusStyle).width)
                    .reduce(math.max) +
                badgeChrome +
                2;
            final badgeWidth =
                math.min(naturalWidth.ceilToDouble(), constraints.maxWidth);
            final textWidth = math.max(1.0, badgeWidth - badgeChrome);
            final badgeHeight = (labels
                        .map((s) =>
                            measure(s, statusStyle, maxWidth: textWidth).height)
                        .reduce(math.max) +
                    12)
                .ceilToDouble();
            final badge = Container(
              key: const ValueKey('request-preview-status'),
              width: badgeWidth,
              height: badgeHeight,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: background, borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 6),
                Flexible(
                    child: Text(label,
                        textAlign: TextAlign.center,
                        style: statusStyle.copyWith(color: foreground))),
              ]),
            );
            final dateWidth =
                measure('00/00/0000', dateStyle).width.ceilToDouble() + 22;
            final date = SizedBox(
              key: const ValueKey('request-preview-date'),
              width: dateWidth,
              child: Row(children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 16, color: _secondary),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(
                        DateFormat('dd/MM/yyyy').format(request.createdAt),
                        style: dateStyle)),
              ]),
            );
            Widget metadata() => LayoutBuilder(builder: (context, available) {
                  if (available.maxWidth >= dateWidth + 10 + badgeWidth) {
                    return Row(
                        children: [date, const SizedBox(width: 10), badge]);
                  }
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [date, const SizedBox(height: 8), badge]);
                });
            final name = Text(request.name,
                key: const ValueKey('request-preview-name'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                    fontSize: 16, fontWeight: FontWeight.w600, color: _text));
            // Larger text can use the whole card for the metadata without
            // squeezing the badge or shrinking the user's chosen text size.
            final useFullWidth = constraints.maxWidth - 80 < badgeWidth;
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFFB1EEC9),
                        foregroundColor: _green,
                        child: Text(initials.isEmpty ? '?' : initials,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w500))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          name,
                          if (!useFullWidth) ...[
                            const SizedBox(height: 8),
                            metadata(),
                          ]
                        ])),
                    if (reviewActions == null) ...[
                      const SizedBox(width: 10),
                      const Icon(Icons.chevron_right, size: 18, color: _text),
                    ],
                  ]),
                  if (useFullWidth) ...[const SizedBox(height: 12), metadata()],
                  if (reviewActions != null) ...[
                    const SizedBox(height: 6),
                    Align(
                        alignment: Alignment.centerRight,
                        child: reviewActions!),
                  ],
                ]);
          }),
        ),
      ),
    );
  }
}
