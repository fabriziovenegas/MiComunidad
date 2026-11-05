import 'package:flutter/material.dart';
import '../models/access_request.dart';
import '../services/private_file_service.dart';
import 'online_action_dialog.dart';

/// Internal administrative view. Files always open via authenticated Storage.
class AccessRequestDocumentLinks extends StatefulWidget {
  const AccessRequestDocumentLinks(
      {super.key, required this.request, this.open, this.isOffline});
  final AccessRequest request;
  final Future<void> Function(AccessRequestDocument document)? open;
  final Future<bool> Function()? isOffline;

  @override
  State<AccessRequestDocumentLinks> createState() =>
      _AccessRequestDocumentLinksState();
}

class _AccessRequestDocumentLinksState
    extends State<AccessRequestDocumentLinks> {
  String? _opening;

  Future<void> _open(AccessRequestDocument document) async {
    if (_opening != null) return;
    setState(() => _opening = document.url);
    try {
      await runOnlineAction(context,
          actionKey: 'open-access-document:${document.url}',
          isOffline: widget.isOffline,
          offlineMessage: 'Necesitas conexión para abrir el documento',
          slowMessage:
              'El documento está tardando en abrirse. Verifica tu conexión',
          successMessage: null,
          errorMessage: (_) =>
              'No se pudo abrir el documento adjunto. Verifica tu conexión y vuelve a intentarlo.',
          action: () => widget.open != null
              ? widget.open!(document)
              : PrivateFileService.open(document.url, name: document.name));
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Documentos de respaldo',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      for (final document in widget.request.documents)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton.icon(
            onPressed: _opening == null ? () => _open(document) : null,
            icon: _opening == document.url
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(document.name.toLowerCase().endsWith('.pdf')
                    ? Icons.picture_as_pdf_outlined
                    : Icons.image_outlined),
            label: Text(_opening == document.url ? 'Abriendo…' : document.name,
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ),
    ]);
  }
}
