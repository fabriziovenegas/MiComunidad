import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/file_service.dart';
import '../services/local_attachment_preview.dart';

Future<void> openSelectedUploadPreview(
    BuildContext context, SelectedUpload selected) async {
  if (FileService.contentTypeForName(selected.name) == 'application/pdf') {
    await LocalAttachmentPreview.openPdf(selected);
  } else {
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => SelectedImagePreview(selected: selected)));
  }
}

class SelectedImagePreview extends StatefulWidget {
  const SelectedImagePreview({super.key, required this.selected});
  final SelectedUpload selected;

  @override
  State<SelectedImagePreview> createState() => _SelectedImagePreviewState();
}

class _SelectedImagePreviewState extends State<SelectedImagePreview> {
  late final Future<Uint8List> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = LocalAttachmentPreview.read(widget.selected);
  }

  Widget _error(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.broken_image_outlined,
                color: Colors.white70, size: 48),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(widget.selected.name,
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        body: SafeArea(
          child: FutureBuilder<Uint8List>(
            future: _bytes,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                final error = snapshot.error;
                return _error(error is FileUploadException
                    ? error.message
                    : 'No se pudo abrir la fotografía. Vuelve a seleccionarla.');
              }
              final bytes = snapshot.data;
              if (bytes == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return InteractiveViewer(
                minScale: .8,
                maxScale: 5,
                child: Center(
                  child: Image.memory(bytes,
                      key: const ValueKey('selected-image-preview'),
                      fit: BoxFit.contain,
                      semanticLabel: 'Vista previa de ${widget.selected.name}',
                      errorBuilder: (_, __, ___) => _error(
                          'No se pudo abrir la fotografía. Vuelve a seleccionarla.')),
                ),
              );
            },
          ),
        ),
      );
}
