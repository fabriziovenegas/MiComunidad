import 'attachment_information.dart';
import 'private_storage_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/private_file_service.dart';

import '../models/user_model.dart';
import '../services/community_service.dart';
import '../utils/text_encoding.dart';
import 'agenda_presentation.dart';
import 'image_gallery_screen.dart';
import 'upload_error_notice.dart';

/// Photo and document subcollections remain separate, regardless of MIME type.
class AgendaAttachments extends StatelessWidget {
  const AgendaAttachments(
      {super.key,
      required this.eventId,
      required this.kind,
      required this.user,
      required this.readOnly,
      this.collection = 'events'})
      : assert(kind == 'photos' || kind == 'minutes'),
        assert(collection == 'events' || collection == 'projects');
  final String collection;
  final String eventId;
  final String kind;
  final AppUser user;
  final bool readOnly;

  bool _isPdf(Map<String, dynamic> data) =>
      data['contentType'] == 'application/pdf' ||
      readableText(data['name']).toLowerCase().endsWith('.pdf');

  Future<void> _open(BuildContext context, Map<String, dynamic> data,
      List<String> imageUrls, Map<String, WidgetBuilder> information) async {
    final url = readableText(data['url']).trim();
    try {
      if (url.isEmpty) throw StateError('Missing attachment URL');
      if (_isPdf(data)) {
        await PrivateFileService.open(url);
      } else {
        final index = imageUrls.indexOf(url);
        if (index < 0 || !context.mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ImageGalleryScreen(
                urls: imageUrls,
                initialIndex: index,
                information: information)));
      }
    } catch (_) {
      if (context.mounted) {
        showUploadError(context, 'No se pudo abrir el archivo.');
      }
    }
  }

  Future<void> _delete(
      BuildContext context, String id, Map<String, dynamic> data) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Eliminar archivo'),
              content: const Text('¿Deseas eliminar este archivo compartido?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Eliminar')),
              ],
            ));
    if (confirmed != true) return;
    try {
      await CommunityService.instance.deleteAttachment(
          collection: collection,
          documentId: eventId,
          kind: kind,
          attachmentId: id,
          storagePath: data['storagePath'] as String?,
          downloadUrl: data['url'] as String?);
    } catch (_) {
      if (context.mounted) {
        showUploadError(
            context, 'No se pudo eliminar el archivo. Inténtalo nuevamente.');
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream:
            CommunityService.instance.attachments(collection, eventId, kind),
        builder: (context, snapshot) {
          final documents = kind == 'minutes';
          if (snapshot.hasError) {
            return Text(
                documents
                    ? 'No se pudieron cargar los documentos.'
                    : 'No se pudieron cargar las fotos.',
                style: TextStyle(color: Theme.of(context).colorScheme.error));
          }
          if (!snapshot.hasData) {
            return SizedBox(
                height: 80,
                child: Center(
                    child: CircularProgressIndicator(
                        semanticsLabel: documents
                            ? 'Cargando documentos'
                            : 'Cargando fotos')));
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            if (documents) {
              return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(collection == 'projects'
                      ? 'Aún no hay documentos del proyecto.'
                      : 'Aún no hay documentos.'));
            }
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                  width: double.infinity,
                  child: Column(children: [
                    Icon(Icons.image_outlined,
                        size: 36, color: Color(0xFF98A09A)),
                    SizedBox(height: 12),
                    Text('Aún no hay fotografías.',
                        style: TextStyle(color: AgendaVisuals.secondaryText)),
                  ])),
            );
          }
          final urls = docs
              .where((doc) => !_isPdf(doc.data()))
              .map((doc) => readableText(doc.data()['url']).trim())
              .where((url) => url.isNotEmpty)
              .toList();
          final information = <String, WidgetBuilder>{
            for (final doc in docs)
              readableText(doc.data()['url']).trim():
                  attachmentInformationBuilder(
                      collection, eventId, kind, doc.id, doc.data()),
          };
          bool canDelete(Map<String, dynamic> data) =>
              !readOnly && (user.isAdmin || data['uploadedBy'] == user.userId);
          if (documents) {
            return Column(children: [
              for (var i = 0; i < docs.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                AgendaDocumentTile(
                    name: readableText(docs[i].data()['name']),
                    isPdf: _isPdf(docs[i].data()),
                    onInfo: () => showDialog<void>(
                        context: context,
                        builder: information[
                            readableText(docs[i].data()['url']).trim()]!),
                    onOpen: () =>
                        _open(context, docs[i].data(), urls, information),
                    onDelete: canDelete(docs[i].data())
                        ? () => _delete(context, docs[i].id, docs[i].data())
                        : null),
              ],
            ]);
          }
          return LayoutBuilder(builder: (context, constraints) {
            final width = ((constraints.maxWidth - 10) / 2).clamp(110.0, 240.0);
            final height = width * .75;
            return SizedBox(
                height: height,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    return SizedBox(
                        width: width,
                        height: height,
                        child: Stack(children: [
                          Positioned.fill(
                              child: InkWell(
                                  onTap: () =>
                                      _open(context, data, urls, information),
                                  child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: PrivateStorageImage(
                                          readableText(data['url']),
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Container(
                                              color: const Color(0xFFE4EBE5),
                                              child: const Center(
                                                  child: Icon(Icons
                                                      .broken_image_outlined))))))),
                          if (canDelete(data))
                            Positioned(
                                top: 3,
                                right: 3,
                                child: IconButton.filledTonal(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Eliminar archivo',
                                    icon: const Icon(Icons.delete_outline,
                                        size: 18),
                                    onPressed: () => _delete(
                                        context, docs[index].id, data))),
                        ]));
                  },
                ));
          });
        },
      );
}
