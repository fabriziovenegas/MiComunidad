import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/user_model.dart';
import '../services/community_service.dart';
import '../services/file_service.dart';
import 'image_gallery_screen.dart';
import '../utils/text_encoding.dart';
import 'content_comment_composer.dart';

class ContentDetailSheet extends StatefulWidget {
  const ContentDetailSheet(
      {super.key,
      required this.collection,
      required this.documentId,
      required this.title,
      required this.user,
      this.allowMinutes = false,
      this.readOnly = false,
      this.allowCommentsWhenReadOnly = false,
      this.footer});
  final String collection;
  final String documentId;
  final String title;
  final AppUser user;
  final bool allowMinutes;
  final bool readOnly;
  final bool allowCommentsWhenReadOnly;
  final Widget? footer;
  @override
  State<ContentDetailSheet> createState() => _ContentDetailSheetState();
}

class _ContentDetailSheetState extends State<ContentDetailSheet> {
  bool _busy = false;
  String? _uploadMessage;
  bool _uploadFailed = false;
  bool get _canAddComments =>
      widget.user.isApproved &&
      (!widget.readOnly ||
          (widget.collection == 'reports' && widget.allowCommentsWhenReadOnly));

  Future<void> _addImage() async {
    final selected = await FileService.pickImage();
    if (selected == null) return;
    await _upload(selected, 'photos');
  }

  Future<void> _addMinutes() async {
    final selected = await FileService.pickIdentityDocument();
    if (selected == null) return;
    await _upload(selected, 'minutes');
  }

  Future<void> _upload(SelectedUpload selected, String kind) async {
    setState(() {
      _busy = true;
      _uploadMessage = null;
      _uploadFailed = false;
    });
    try {
      final queued = await CommunityService.instance.addAttachment(
          collection: widget.collection,
          documentId: widget.documentId,
          kind: kind,
          selected: selected);
      if (mounted) {
        setState(() {
          _uploadMessage = queued
              ? 'Sin conexión: el archivo quedó guardado y se subirá automáticamente.'
              : 'Archivo compartido correctamente.';
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(queued
              ? 'Sin conexión: el archivo quedó guardado y se subirá automáticamente.'
              : 'Archivo compartido.'),
        ));
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _uploadFailed = true;
          _uploadMessage = 'No se pudo subir el archivo: $error';
        });
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo subir el archivo: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendComment(String text) async {
    if (_busy || !_canAddComments) {
      throw StateError('No se puede enviar un comentario en este momento.');
    }
    setState(() => _busy = true);
    try {
      await CommunityService.instance.addComment(
          collection: widget.collection,
          documentId: widget.documentId,
          text: text,
          authorName: widget.user.nombre);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .88,
      maxChildSize: .96,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 26),
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.headlineSmall),
          if (widget.readOnly) ...[
            const SizedBox(height: 8),
            Text(_canAddComments
                ? 'Puedes comentar. Los archivos permanecen en modo de solo lectura.'
                : 'Vista de solo lectura.'),
          ],
          const SizedBox(height: 16),
          if (!widget.readOnly)
            Row(children: [
              Expanded(
                  child: OutlinedButton.icon(
                      onPressed: _busy ? null : _addImage,
                      icon: const Icon(Icons.add_photo_alternate),
                      label: const Text('Subir JPG/PNG'))),
              if (widget.allowMinutes) ...[
                const SizedBox(width: 10),
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: _busy ? null : _addMinutes,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Subir acta')))
              ]
            ]),
          if (_uploadMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _uploadFailed
                    ? Theme.of(context).colorScheme.errorContainer
                    : Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_uploadMessage!),
            ),
          ],
          const SizedBox(height: 16),
          Text('Archivos compartidos',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _Attachments(
              collection: widget.collection,
              documentId: widget.documentId,
              kind: 'photos',
              user: widget.user,
              readOnly: widget.readOnly),
          if (widget.allowMinutes)
            _Attachments(
                collection: widget.collection,
                documentId: widget.documentId,
                kind: 'minutes',
                user: widget.user,
                readOnly: widget.readOnly),
          const Divider(height: 28),
          Text('Comentarios', style: Theme.of(context).textTheme.titleMedium),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: CommunityService.instance
                .comments(widget.collection, widget.documentId),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? const [];
              if (docs.isEmpty) {
                return Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(!_canAddComments
                        ? 'No hay comentarios.'
                        : 'Sé la primera persona en comentar.'));
              }
              return Column(
                  children: docs.map((doc) {
                final data = doc.data();
                final date = (data['createdAt'] as Timestamp?)?.toDate();
                return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(readableText(data['authorName']).isEmpty
                        ? 'Vecino'
                        : readableText(data['authorName'])),
                    subtitle: Text(readableText(data['text'])),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (date != null) Text(DateFormat('dd/MM').format(date)),
                      if (!widget.readOnly &&
                          (widget.user.isAdmin ||
                              data['authorId'] == widget.user.userId))
                        IconButton(
                          tooltip: 'Eliminar comentario',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteComment(doc.id),
                        ),
                    ]));
              }).toList());
            },
          ),
          if (_canAddComments)
            ContentCommentComposer(enabled: !_busy, onSend: _sendComment),
          if (widget.footer != null) ...[
            const SizedBox(height: 24),
            widget.footer!,
          ],
        ],
      ),
    );
  }

  Future<void> _deleteComment(String commentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar comentario'),
        content: const Text('¿Deseas eliminar este comentario?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await CommunityService.instance.deleteComment(
        collection: widget.collection,
        documentId: widget.documentId,
        commentId: commentId,
      );
    }
  }
}

class _Attachments extends StatelessWidget {
  const _Attachments(
      {required this.collection,
      required this.documentId,
      required this.kind,
      required this.user,
      required this.readOnly});
  final String collection;
  final String documentId;
  final String kind;
  final AppUser user;
  final bool readOnly;
  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream:
            CommunityService.instance.attachments(collection, documentId, kind),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? const [];
          if (docs.isEmpty) return const SizedBox.shrink();
          return SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final data = docs[index].data();
                final url = data['url'] as String? ?? '';
                final isPdf = data['contentType'] == 'application/pdf';
                final imageDocuments = docs
                    .where((document) =>
                        document.data()['contentType'] != 'application/pdf')
                    .toList();
                final imageUrls = imageDocuments
                    .map((document) => document.data()['url'] as String? ?? '')
                    .where((value) => value.isNotEmpty)
                    .toList();
                final galleryIndex = imageUrls.indexOf(url);
                final canDelete = !readOnly &&
                    (user.isAdmin || data['uploadedBy'] == user.userId);
                return Stack(children: [
                  InkWell(
                    onTap: () {
                      if (isPdf) {
                        launchUrl(Uri.parse(url),
                            mode: LaunchMode.externalApplication);
                        return;
                      }
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ImageGalleryScreen(
                          urls: imageUrls,
                          initialIndex: galleryIndex < 0 ? 0 : galleryIndex,
                        ),
                      ));
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: isPdf
                          ? Container(
                              width: 110,
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.picture_as_pdf, size: 38),
                                    Text('Acta PDF')
                                  ]))
                          : Image.network(url,
                              width: 110,
                              height: 110,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox(
                                  width: 110, child: Icon(Icons.broken_image))),
                    ),
                  ),
                  if (canDelete)
                    Positioned(
                      top: 3,
                      right: 3,
                      child: IconButton.filledTonal(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Eliminar archivo',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Eliminar archivo'),
                              content: const Text(
                                  '¿Deseas eliminar este archivo compartido?'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancelar'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Eliminar'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed != true) return;
                          await CommunityService.instance.deleteAttachment(
                            collection: collection,
                            documentId: documentId,
                            kind: kind,
                            attachmentId: docs[index].id,
                            storagePath: data['storagePath'] as String?,
                            downloadUrl: url,
                          );
                        },
                      ),
                    ),
                ]);
              },
            ),
          );
        },
      );
}
