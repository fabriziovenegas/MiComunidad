import 'dart:io';
import 'package:flutter/material.dart';
import '../services/access_request_document_picker.dart';
import '../services/file_service.dart';
import 'selected_upload_preview.dart';
import 'upload_error_notice.dart';
import 'upload_picker.dart';

class AccessRequestDocumentsSection extends StatefulWidget {
  const AccessRequestDocumentsSection({
    super.key,
    required this.documents,
    required this.onChanged,
    this.enabled = true,
    this.pick,
    this.recover,
  });

  final List<SelectedUpload> documents;
  final ValueChanged<List<SelectedUpload>> onChanged;
  final bool enabled;
  final Future<SelectedUpload?> Function(AccessDocumentSource source)? pick;
  final Future<List<SelectedUpload>> Function()? recover;

  @override
  State<AccessRequestDocumentsSection> createState() =>
      _AccessRequestDocumentsSectionState();
}

class _AccessRequestDocumentsSectionState
    extends State<AccessRequestDocumentsSection> {
  final _picker = AccessRequestDocumentPicker();
  bool _picking = false;
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    // Photo-picker results can survive Android reclaiming the activity.
    if ((widget.pick == null && Platform.isAndroid) || widget.recover != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recover());
    }
  }

  Future<void> _recover() async {
    if (!mounted) return;
    await pickUploadWithFeedback(context, () async {
      final files = await (widget.recover ?? _picker.recoverLostImages)();
      if (!mounted || !widget.enabled) return null;
      final room = 3 - widget.documents.length;
      if (files.isNotEmpty && room > 0) {
        widget.onChanged([...widget.documents, ...files.take(room)]);
      }
      return null;
    });
  }

  Future<void> _add() async {
    if (!widget.enabled ||
        _picking ||
        _previewing ||
        widget.documents.length >= 3) {
      return;
    }
    setState(() => _picking = true);
    try {
      final source = await showModalBottomSheet<AccessDocumentSource>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final entry in const [
              (
                AccessDocumentSource.camera,
                Icons.photo_camera_outlined,
                'Tomar foto'
              ),
              (
                AccessDocumentSource.gallery,
                Icons.photo_library_outlined,
                'Elegir de galería'
              ),
              (
                AccessDocumentSource.file,
                Icons.attach_file,
                'Seleccionar archivo'
              ),
            ])
              ListTile(
                leading: Icon(entry.$2),
                title: Text(entry.$3),
                onTap: () => Navigator.pop(sheetContext, entry.$1),
              ),
          ]),
        ),
      );
      if (!mounted || source == null || !widget.enabled) return;
      final selected = await pickUploadWithFeedback(context, () async {
        final file = await (widget.pick ?? _picker.pick)(source);
        return file == null
            ? null
            : FileService.prepareIdentityDocument(file.file);
      });
      if (mounted &&
          widget.enabled &&
          selected != null &&
          widget.documents.length < 3) {
        widget.onChanged([...widget.documents, selected]);
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _preview(SelectedUpload selected) async {
    if (!widget.enabled || _picking || _previewing) return;
    setState(() => _previewing = true);
    try {
      await openSelectedUploadPreview(context, selected);
    } catch (error) {
      if (mounted) {
        showUploadError(
            context,
            error is FileUploadException
                ? error.message
                : 'No se pudo abrir el archivo. Inténtalo nuevamente.');
      }
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  static String sizeLabel(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB'
      : '${(bytes / 1024).ceil()} KB';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = widget.enabled && !_picking && !_previewing;
    return Container(
      key: const ValueKey('access-request-documents'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
              child: Text('Documentos de respaldo',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700))),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: const Color(0xFFD8F7E4),
                borderRadius: BorderRadius.circular(20)),
            child: Text('${widget.documents.length} de 3',
                key: const ValueKey('document-count')),
          ),
        ]),
        const SizedBox(height: 10),
        const Text(
            'Adjunta un recibo de agua de tu vivienda o una foto legible de tu DNI.'),
        const SizedBox(height: 6),
        Text('Hasta 3 archivos · Máximo 5 MB por archivo',
            style: theme.textTheme.bodySmall),
        for (var index = 0; index < widget.documents.length; index++) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Ver ${widget.documents[index].name}',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: ValueKey('preview-document-$index'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: active
                          ? () => _preview(widget.documents[index])
                          : null,
                      child: Row(children: [
                        Icon(
                            FileService.extensionOf(
                                        widget.documents[index].name) ==
                                    'pdf'
                                ? Icons.picture_as_pdf_outlined
                                : Icons.image_outlined,
                            color: theme.colorScheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(widget.documents[index].name,
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                              Text(sizeLabel(widget.documents[index].size),
                                  style: theme.textTheme.bodySmall),
                            ]))
                      ]),
                    ),
                  ),
                ),
              ),
              IconButton(
                key: ValueKey('remove-document-$index'),
                tooltip: 'Quitar ${widget.documents[index].name}',
                onPressed: active
                    ? () => widget.onChanged([
                          for (var i = 0; i < widget.documents.length; i++)
                            if (i != index) widget.documents[i]
                        ])
                    : null,
                icon: const Icon(Icons.close),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('add-access-document'),
          onPressed: active && widget.documents.length < 3 ? _add : null,
          icon: const Icon(Icons.add),
          label: const Text('Añadir archivo'),
        ),
        const SizedBox(height: 6),
        Text('JPG, JPEG, PNG, WEBP, HEIC, HEIF o PDF',
            style: theme.textTheme.bodySmall),
      ]),
    );
  }
}
