import 'package:flutter/material.dart';
import '../services/pending_upload_service.dart';
import '../services/attachment_delivery.dart';

class PendingAttachmentsNotice extends StatefulWidget {
  const PendingAttachmentsNotice(
      {super.key,
      required this.collection,
      this.documentId,
      required this.userId,
      this.service});
  final String collection;
  final String? documentId;
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
                (widget.documentId == null ||
                    item.documentId == widget.documentId))
            .toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return Card(
            child: ExpansionTile(
                leading: const Icon(Icons.cloud_upload_outlined),
                title: Text(items.length == 1
                    ? '1 archivo pendiente de envío'
                    : '${items.length} archivos pendientes de envío'),
                subtitle: const Text('Guardados en este teléfono.'),
                children: [
              for (final item in items)
                ListTile(
                    title: Text(item.name),
                    subtitle: Text(item.blocked
                        ? item.reason ??
                            'No se pudo completar el envío. La copia sigue guardada.'
                        : 'El envío sigue pendiente. Se reintentará con la app abierta.')),
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
