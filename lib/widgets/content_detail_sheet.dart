import 'private_storage_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/private_file_service.dart';
import '../models/user_model.dart';
import '../services/community_service.dart';
import '../services/file_service.dart';
import 'image_gallery_screen.dart';
import '../utils/text_encoding.dart';
import 'content_comment_composer.dart';
import 'upload_picker.dart';
import 'upload_error_notice.dart';
import 'content_information.dart';
import 'project_presentation.dart';
import 'agenda_attachments.dart';
import '../services/pending_content_service.dart';
import 'pending_content_notice.dart';
import 'pending_attachments_notice.dart';

class ContentDetailSheet extends StatefulWidget {
  const ContentDetailSheet(
      {super.key,
      required this.collection,
      required this.documentId,
      required this.title,
      required this.user,
      this.data = const {},
      this.allowMinutes = false,
      this.readOnly = false,
      this.allowCommentsWhenReadOnly = false,
      this.pendingContent,
      this.footer});
  final String collection;
  final String documentId;
  final String title;
  final AppUser user;
  final Map<String, dynamic> data;
  final bool allowMinutes;
  final bool readOnly;
  final bool allowCommentsWhenReadOnly;
  final Widget? footer;
  final PendingContentService? pendingContent;
  @override
  State<ContentDetailSheet> createState() => _ContentDetailSheetState();
}

class _ContentDetailSheetState extends State<ContentDetailSheet> {
  bool _busy = false;
  String? _uploadMessage;
  bool _uploadFailed = false;
  String? _uploadKind;
  PendingContentService get _outbox =>
      widget.pendingContent ?? PendingContentService.instance;
  bool get _canAddComments =>
      widget.user.isApproved &&
      (!widget.readOnly ||
          (widget.collection == 'reports' && widget.allowCommentsWhenReadOnly));

  Future<void> _addImage() async {
    final selected =
        await pickUploadWithFeedback(context, FileService.pickImage);
    if (selected == null) return;
    await _upload(selected, 'photos');
  }

  Future<void> _addMinutes() async {
    final selected =
        await pickUploadWithFeedback(context, FileService.pickIdentityDocument);
    if (selected == null) return;
    await _upload(selected, 'minutes');
  }

  Future<void> _upload(SelectedUpload selected, String kind) async {
    setState(() {
      _busy = true;
      _uploadMessage = null;
      _uploadFailed = false;
      _uploadKind = kind;
    });
    try {
      final result = await CommunityService.instance.addAttachment(
          collection: widget.collection,
          documentId: widget.documentId,
          kind: kind,
          selected: selected);
      if (mounted) {
        final message = switch (result.state) {
          PendingSendState.sent => 'Archivo subido correctamente.',
          PendingSendState.queued => result.reason == null
              ? 'Guardado en este teléfono. Pendiente de envío.'
              : 'Archivo guardado en este teléfono. ${result.reason}',
          PendingSendState.blocked =>
            'Archivo guardado en este dispositivo. ${result.reason} Revisa los pendientes.',
        };
        setState(() {
          // Pending/blocked uploads are shown by their section's live queue notice.
          // Keeping the initial result here would outlive a later confirmation.
          _uploadMessage =
              result.state == PendingSendState.sent ? message : null;
          _uploadFailed =
              result.state == PendingSendState.blocked || result.reason != null;
        });
        if (result.state == PendingSendState.blocked || result.reason != null) {
          showUploadError(context, message);
        } else {
          showSuccessNotice(context, message);
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _uploadFailed = true;
          _uploadMessage = 'No se pudo subir el archivo: $error';
        });
        showUploadError(context, 'No se pudo subir el archivo: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<PendingSendResult> _sendComment(String text) async {
    if (_busy || !_canAddComments) {
      throw StateError('No se puede enviar un comentario en este momento.');
    }
    setState(() => _busy = true);
    try {
      return await _outbox.submit(
          id: _outbox.newId(),
          expectedUserId: widget.user.userId,
          collection: widget.collection,
          parentId: widget.documentId,
          fields: {'text': text.trim(), 'authorName': widget.user.nombre});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isProject = widget.collection == 'projects';
    final isReport = widget.collection == 'reports';
    final isAgenda = widget.collection == 'events';
    final photoLayout = isProject || isReport || isAgenda;
    final sectionStyle = photoLayout
        ? Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: ProjectVisuals.text,
            fontSize: 20)
        : Theme.of(context).textTheme.titleMedium;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .88,
      maxChildSize: .96,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: EdgeInsets.fromLTRB(
            photoLayout ? 20 : 18,
            0,
            photoLayout ? 20 : 18,
            26 + (photoLayout ? MediaQuery.viewInsetsOf(context).bottom : 0)),
        children: [
          Text(widget.title,
              style: photoLayout
                  ? Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700, color: ProjectVisuals.text)
                  : Theme.of(context).textTheme.headlineSmall),
          if (widget.readOnly) ...[
            const SizedBox(height: 8),
            Text(_canAddComments
                ? 'Puedes comentar. Los archivos permanecen en modo de solo lectura.'
                : 'Vista de solo lectura.'),
          ],
          SizedBox(height: photoLayout ? 20 : 16),
          if (widget.data.isNotEmpty)
            ContentInformation(
                collection: widget.collection,
                data: widget.data,
                documentId: widget.documentId,
                reportId: isReport ? widget.documentId : null,
                user: widget.user),
          if (!photoLayout && !widget.readOnly)
            Row(children: [
              Expanded(
                  child: OutlinedButton.icon(
                      onPressed: _busy ? null : _addImage,
                      icon: const Icon(Icons.add_photo_alternate),
                      label: const Text('Añadir fotografía'))),
              if (widget.allowMinutes) ...[
                const SizedBox(width: 10),
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: _busy ? null : _addMinutes,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Subir acta')))
              ]
            ]),
          if (!photoLayout && _uploadMessage != null) ...[
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
          if (!photoLayout) const SizedBox(height: 16),
          Text(photoLayout ? 'Fotos compartidas' : 'Archivos compartidos',
              style: sectionStyle),
          SizedBox(height: photoLayout ? 16 : 8),
          PendingAttachmentsNotice(
              collection: widget.collection,
              documentId: widget.documentId,
              kind: photoLayout ? 'photos' : null,
              userId: widget.user.userId),
          if (isAgenda)
            AgendaAttachments(
                eventId: widget.documentId,
                kind: 'photos',
                user: widget.user,
                readOnly: widget.readOnly)
          else
            _Attachments(
                collection: widget.collection,
                documentId: widget.documentId,
                kind: 'photos',
                user: widget.user,
                readOnly: widget.readOnly,
                showPhotosEmptyState: photoLayout),
          if (photoLayout && !widget.readOnly) ...[
            const SizedBox(height: 16),
            SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _addImage,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ProjectVisuals.green,
                    minimumSize: const Size(0, 52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.add_photo_alternate),
                  label: const Text('Añadir fotografía'),
                )),
          ],
          if (photoLayout &&
              _uploadMessage != null &&
              (!isAgenda || _uploadKind != 'minutes')) ...[
            const SizedBox(height: 12),
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
          if (widget.allowMinutes) ...[
            if (isAgenda) ...[
              const Divider(height: 44),
              Text('Actas y documentos', style: sectionStyle),
              const SizedBox(height: 16),
              PendingAttachmentsNotice(
                  collection: widget.collection,
                  documentId: widget.documentId,
                  kind: 'minutes',
                  userId: widget.user.userId),
              AgendaAttachments(
                  eventId: widget.documentId,
                  kind: 'minutes',
                  user: widget.user,
                  readOnly: widget.readOnly),
              if (!widget.readOnly) ...[
                const SizedBox(height: 16),
                SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                        onPressed: _busy ? null : _addMinutes,
                        style: OutlinedButton.styleFrom(
                            foregroundColor: ProjectVisuals.green,
                            minimumSize: const Size(0, 52),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))),
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Adjuntar acta'))),
              ],
              if (_uploadKind == 'minutes' && _uploadMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: _uploadFailed
                            ? Theme.of(context).colorScheme.errorContainer
                            : Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12)),
                    child: Text(_uploadMessage!)),
              ],
            ] else
              _Attachments(
                  collection: widget.collection,
                  documentId: widget.documentId,
                  kind: 'minutes',
                  user: widget.user,
                  readOnly: widget.readOnly),
          ],
          Divider(height: photoLayout ? 44 : 28),
          Text('Comentarios', style: sectionStyle),
          PendingContentNotice(
              userId: widget.user.userId,
              collection: widget.collection,
              parentId: widget.documentId,
              service: _outbox),
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
            ContentCommentComposer(
                enabled: !_busy,
                onSendPending: _sendComment,
                projectStyle: photoLayout),
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
      required this.readOnly,
      this.showPhotosEmptyState = false});
  final String collection;
  final String documentId;
  final String kind;
  final AppUser user;
  final bool readOnly;
  final bool showPhotosEmptyState;
  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream:
            CommunityService.instance.attachments(collection, documentId, kind),
        builder: (context, snapshot) {
          if (showPhotosEmptyState && snapshot.hasError) {
            return Text('No se pudieron cargar las fotos.',
                style: TextStyle(color: Theme.of(context).colorScheme.error));
          }
          if (showPhotosEmptyState && !snapshot.hasData) {
            return const SizedBox(
                height: 80,
                child: Center(
                    child: CircularProgressIndicator(
                        semanticsLabel: 'Cargando fotos')));
          }
          final docs = snapshot.data?.docs ?? const [];
          if (docs.isEmpty) {
            return showPhotosEmptyState
                ? const ProjectPhotosEmptyState()
                : const SizedBox.shrink();
          }
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
                    onTap: () async {
                      if (isPdf) {
                        try {
                          await PrivateFileService.open(url);
                        } catch (_) {
                          if (context.mounted) {
                            showUploadError(
                                context, 'No se pudo abrir el archivo.');
                          }
                        }
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
                          : PrivateStorageImage(url,
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
