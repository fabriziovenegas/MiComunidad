import 'package:flutter/material.dart';
import '../services/file_service.dart';
import '../services/photo_picker.dart';
import 'photo_source_menu.dart';
import 'upload_error_notice.dart';

class ReportPhotosSection extends StatefulWidget {
  const ReportPhotosSection(
      {super.key,
      required this.photos,
      required this.onChanged,
      required this.onPickingChanged,
      this.enabled = true,
      this.pick});

  final List<SelectedUpload> photos;
  final ValueChanged<List<SelectedUpload>> onChanged;
  final ValueChanged<bool> onPickingChanged;
  final bool enabled;
  final Future<PhotoSelection> Function(BuildContext)? pick;

  @override
  State<ReportPhotosSection> createState() => _ReportPhotosSectionState();
}

class _ReportPhotosSectionState extends State<ReportPhotosSection> {
  bool _picking = false;

  Future<void> _add() async {
    if (_picking || !widget.enabled || widget.photos.length >= 3) return;
    setState(() => _picking = true);
    widget.onPickingChanged(true);
    try {
      final selected =
          await (widget.pick?.call(context) ?? pickPhotosWithMenu(context));
      if (!mounted || !widget.enabled) return;
      final remaining = 3 - widget.photos.length;
      if (selected.photos.length > remaining) {
        showUploadError(context, 'Puedes adjuntar hasta 3 fotografías.');
      }
      widget.onChanged([...widget.photos, ...selected.photos.take(remaining)]);
    } finally {
      if (mounted) {
        setState(() => _picking = false);
        widget.onPickingChanged(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = widget.enabled && !_picking;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
              child: Text('Fotografías (opcional)',
                  style: theme.textTheme.titleSmall)),
          const SizedBox(width: 8),
          Text('${widget.photos.length} de 3'),
        ]),
        const SizedBox(height: 6),
        Text('Hasta 3 fotos · Máximo 10 MB por foto',
            style: theme.textTheme.bodySmall),
        for (var i = 0; i < widget.photos.length; i++)
          Row(children: [
            Icon(Icons.image_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(widget.photos[i].name,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(
                      '${(widget.photos[i].size / (1024 * 1024)).toStringAsFixed(1)} MB',
                      style: theme.textTheme.bodySmall),
                ])),
            IconButton(
                tooltip: 'Quitar ${widget.photos[i].name}',
                onPressed: active
                    ? () => widget.onChanged([
                          for (var j = 0; j < widget.photos.length; j++)
                            if (j != i) widget.photos[j]
                        ])
                    : null,
                icon: const Icon(Icons.close)),
          ]),
        const SizedBox(height: 8),
        OutlinedButton.icon(
            onPressed: active && widget.photos.length < 3 ? _add : null,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(_picking ? 'Seleccionando…' : 'Añadir fotografía')),
      ]),
    );
  }
}
