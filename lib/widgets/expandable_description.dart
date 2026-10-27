import 'package:flutter/material.dart';

/// Limits reading-only descriptions to four rendered lines, not a character count.
class ExpandableDescription extends StatefulWidget {
  const ExpandableDescription(
      {super.key, required this.text, this.style, this.heading});

  final String text;
  final TextStyle? style;
  final String? heading;

  @override
  State<ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<ExpandableDescription> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant ExpandableDescription oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text) _expanded = false;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final defaults = DefaultTextStyle.of(context);
          var style = defaults.style.merge(widget.style);
          if (MediaQuery.boldTextOf(context)) {
            style = style.copyWith(fontWeight: FontWeight.bold);
          }
          final painter = TextPainter(
            text: TextSpan(text: widget.text, style: style),
            textDirection: Directionality.of(context),
            textAlign: defaults.textAlign ?? TextAlign.start,
            textScaler: MediaQuery.textScalerOf(context),
            locale: Localizations.maybeLocaleOf(context),
            textHeightBehavior: defaults.textHeightBehavior,
            maxLines: 4,
            ellipsis: '…',
          )..layout(maxWidth: constraints.maxWidth);
          final canExpand = painter.didExceedMaxLines;
          painter.dispose();

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.heading != null && widget.text.trim().isNotEmpty) ...[
                Semantics(
                  header: true,
                  child: Text(widget.heading!,
                      textAlign: TextAlign.start,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                widget.text,
                style: style,
                maxLines: canExpand && !_expanded ? 4 : null,
                overflow: canExpand && !_expanded
                    ? TextOverflow.ellipsis
                    : TextOverflow.visible,
              ),
              if (canExpand)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Semantics(
                    expanded: _expanded,
                    child: TextButton(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        minimumSize: const Size(48, 48),
                        alignment: AlignmentDirectional.centerStart,
                      ),
                      child: Text(_expanded ? 'Leer menos' : 'Leer más'),
                    ),
                  ),
                ),
            ],
          );
        },
      );
}
