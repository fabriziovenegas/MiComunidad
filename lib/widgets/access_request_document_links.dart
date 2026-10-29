import 'package:flutter/material.dart';
import '../models/access_request.dart';
import '../services/private_file_service.dart';

/// Internal administrative view. Files always open via authenticated Storage.
class AccessRequestDocumentLinks extends StatelessWidget {
  const AccessRequestDocumentLinks(
      {super.key, required this.request, this.open});
  final AccessRequest request;
  final Future<void> Function(AccessRequestDocument document)? open;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Documentos de respaldo',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      for (final document in request.documents)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton.icon(
            onPressed: () async {
              try {
                if (open != null) {
                  await open!(document);
                } else {
                  await PrivateFileService.open(document.url,
                      name: document.name);
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('No se pudo abrir el documento adjunto.')));
                }
              }
            },
            icon: Icon(document.name.toLowerCase().endsWith('.pdf')
                ? Icons.picture_as_pdf_outlined
                : Icons.image_outlined),
            label: Text(document.name,
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ),
    ]);
  }
}
