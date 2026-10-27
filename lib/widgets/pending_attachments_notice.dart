import 'package:flutter/material.dart';
import '../services/pending_upload_service.dart';
import '../services/attachment_delivery.dart';

class PendingAttachmentsNotice extends StatefulWidget {
  const PendingAttachmentsNotice(
      {super.key,
      required this.collection,
      this.documentId,
      this.kind,
      required this.userId,
      this.service});
  final String collection;
  final String? documentId;
  final String? kind;
  final String userId;
  final PendingUploadService? service;
  @override
  State<PendingAttachmentsNotice> createState() =>
      _PendingAttachmentsNoticeState();
}

class _PendingAttachmentsNoticeState extends State<PendingAttachmentsNotice> {
  late Stream<List<PendingAttachment>> _items;
  bool _retrying = false;
  PendingUploadService get _service =>
      widget.service ?? PendingUploadService.instance;
  @override
  void initState() {
    super.initState();
    _items = _service.watch(widget.userId);
  }

  @override
  void didUpdateWidget(covariant PendingAttachmentsNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.service != widget.service) {
      _items = _service.watch(widget.userId);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<PendingAttachment>>(
      stream: _items,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text(
              'No se pudieron consultar los archivos pendientes.');
        }
        final items = (snapshot.data ?? [])
            .where((item) =>
                item.collection == widget.collection &&
                (widget.kind == null || item.kind == widget.kind) &&
                (widget.documentId == null ||
                    item.documentId == widget.documentId))
            .toList();
        if (items.isEmpty) return const SizedBox.shrink();
        final waiting = items
            .where((item) =>
                item.waitingForConnection &&
                !item.blocked &&
                item.reason == null)
            .toList();
        final failed =
            items.where((item) => item.blocked || item.reason != null).toList();
        final uploading = items.length - waiting.length - failed.length;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (uploading > 0)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(children: [
                      const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(uploading == 1
                              ? 'Subiendo archivo…'
                              : 'Subiendo $uploading archivos…')),
                    ])),
              if (failed.isNotEmpty)
                Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('No se pudo completar la subida.'),
                          for (final item in failed)
                            ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(item.name),
                                subtitle: Text(item.reason ??
                                    'La copia sigue guardada en este teléfono.')),
                          TextButton(
                              onPressed: _retrying ? null : _retry,
                              child: Text(
                                  _retrying ? 'Reintentando…' : 'Reintentar')),
                        ])),
              if (waiting.isNotEmpty)
                Card(
                    child: ExpansionTile(
                        leading: const Icon(Icons.cloud_upload_outlined),
                        title: Text(waiting.length == 1
                            ? '1 archivo pendiente de envío'
                            : '${waiting.length} archivos pendientes de envío'),
                        subtitle: const Text('Guardados en este teléfono.'),
                        children: [
                      for (final item in waiting)
                        ListTile(
                            title: Text(item.name),
                            subtitle: const Text(
                                'Se subirá cuando se restablezca la conexión, con la aplicación abierta.')),
                      TextButton(
                          onPressed: _retrying ? null : _retry,
                          child:
                              Text(_retrying ? 'Reintentando…' : 'Reintentar'))
                    ])),
            ]);
      });

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      await _service.processPending(retryBlocked: true);
    } catch (_) {
      // The durable copies remain available for another retry.
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }
}
