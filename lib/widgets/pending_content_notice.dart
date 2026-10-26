import 'package:flutter/material.dart';
import '../services/pending_content_service.dart';
import 'pending_attachments_notice.dart';

/// Keep failed contributions reachable even when their parent was deleted.
class PendingCollectionNotice extends StatelessWidget {
  const PendingCollectionNotice(
      {super.key,
      required this.userId,
      required this.collection,
      this.service});
  final String userId;
  final String collection;
  final PendingContentService? service;
  @override
  Widget build(BuildContext context) => Column(children: [
        if (collection != 'reports')
          PendingContentNotice(
              userId: userId, collection: collection, service: service),
        PendingContentNotice(
            userId: userId,
            collection: collection,
            commentsOnly: true,
            service: service),
        PendingAttachmentsNotice(collection: collection, userId: userId),
      ]);
}

class PendingContentNotice extends StatefulWidget {
  const PendingContentNotice(
      {super.key,
      required this.userId,
      required this.collection,
      this.parentId,
      this.service,
      this.commentsOnly = false});
  final String userId;
  final String collection;
  final String? parentId;
  final PendingContentService? service;
  final bool commentsOnly;
  @override
  State<PendingContentNotice> createState() => _PendingContentNoticeState();
}

class _PendingContentNoticeState extends State<PendingContentNotice> {
  late Stream<List<PendingContent>> _items;
  bool _retrying = false;
  PendingContentService get _service =>
      widget.service ?? PendingContentService.instance;
  @override
  void initState() {
    super.initState();
    _items = _service.watch(widget.userId);
  }

  @override
  void didUpdateWidget(covariant PendingContentNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.service != widget.service) {
      _items = _service.watch(widget.userId);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<PendingContent>>(
      stream: _items,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text(
              'No se pudieron consultar los envíos guardados en este teléfono.');
        }
        final items = (snapshot.data ?? [])
            .where((item) =>
                item.collection == widget.collection &&
                (widget.commentsOnly
                    ? item.isComment &&
                        (widget.parentId == null ||
                            item.parentId == widget.parentId)
                    : item.parentId == widget.parentId))
            .toList();
        if (items.isEmpty) return const SizedBox.shrink();
        final noun = widget.commentsOnly || widget.parentId != null
            ? 'comentario'
            : widget.collection == 'projects'
                ? 'proyecto'
                : 'actividad';
        final plural = widget.commentsOnly || widget.parentId != null
            ? 'comentarios'
            : widget.collection == 'projects'
                ? 'proyectos'
                : 'actividades';
        return Card(
            child: ExpansionTile(
                leading: const Icon(Icons.cloud_upload_outlined),
                title: Text(items.length == 1
                    ? '1 $noun pendiente de envío'
                    : '${items.length} $plural pendientes de envío'),
                subtitle: const Text('Guardados en este teléfono.'),
                children: [
              for (final item in items)
                ListTile(
                    onTap: item.isComment
                        ? () => showDialog<void>(
                            context: context,
                            builder: (context) => AlertDialog(
                                    title: const Text('Comentario pendiente'),
                                    content: SingleChildScrollView(
                                        child: SelectableText(item.label)),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text('Cerrar'))
                                    ]))
                        : null,
                    title: Text(item.label,
                        maxLines: 3, overflow: TextOverflow.ellipsis),
                    subtitle: Text(item.blocked
                        ? item.reason ??
                            'No se pudo completar el envío. La copia sigue guardada.'
                        : 'Se enviará cuando tengas conexión y abras la app.')),
              TextButton(
                  onPressed: _retrying
                      ? null
                      : () async {
                          setState(() => _retrying = true);
                          try {
                            await _service.processPending(retryBlocked: true);
                          } catch (_) {
                            // The durable copies remain visible for another retry.
                          } finally {
                            if (mounted) setState(() => _retrying = false);
                          }
                        },
                  child: Text(_retrying ? 'Reintentando…' : 'Reintentar'))
            ]));
      });
}
