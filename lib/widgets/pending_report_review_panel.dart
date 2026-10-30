import 'package:flutter/material.dart';

/// Presentation only; opening and moderation stay with the reports screen.
class PendingReportReviewPanel extends StatelessWidget {
  const PendingReportReviewPanel({super.key, required this.children});

  final List<Widget> children;

  static const green = Color(0xFF245F45);
  static const border = Color(0xFFB6CDBF);

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: border),
        ),
        child: Column(
          children: [
            ColoredBox(
              color: const Color(0xFFE1F0E7),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(children: [
                  const Icon(Icons.assignment_outlined, color: green, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Reportes por aprobar',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                color: green, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 12),
                  Semantics(
                    label: '${children.length} reportes por aprobar',
                    child: ExcludeSemantics(
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 32),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                            color: const Color(0xFFBFE1CB),
                            borderRadius: BorderRadius.circular(10)),
                        child: Text('${children.length}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                    color: green, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            for (final child in children) ...[
              const Divider(height: 1, thickness: 1, color: Color(0xFFD8E4DC)),
              child,
            ],
          ],
        ),
      );
}

class PendingReportReviewRow extends StatelessWidget {
  const PendingReportReviewRow({
    super.key,
    required this.title,
    required this.description,
    required this.onOpen,
    required this.onReject,
    required this.onApprove,
  });

  final String title;
  final String description;
  final VoidCallback onOpen;
  final VoidCallback onReject;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  if (description.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: const Color(0xFF59635E))),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Rechazar',
              color: const Color(0xFFAD5555),
              onPressed: onReject,
              icon: const Icon(Icons.close),
            ),
            IconButton(
              tooltip: 'Aprobar',
              color: PendingReportReviewPanel.green,
              onPressed: onApprove,
              icon: const Icon(Icons.check_circle_outline),
            ),
          ]),
        ),
      );
}
