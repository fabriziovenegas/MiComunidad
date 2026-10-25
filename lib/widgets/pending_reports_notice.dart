import 'package:flutter/material.dart';
import '../services/pending_report_service.dart';

class PendingReportsNotice extends StatefulWidget {
  const PendingReportsNotice(
      {super.key, required this.userId, required this.service});
  final String userId;
  final PendingReportService service;

  @override
  State<PendingReportsNotice> createState() => _PendingReportsNoticeState();
}

class _PendingReportsNoticeState extends State<PendingReportsNotice> {
  late Stream<List<PendingReport>> _pending;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _pending = widget.service.watch(widget.userId);
  }

  @override
  void didUpdateWidget(covariant PendingReportsNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userId != oldWidget.userId ||
        widget.service != oldWidget.service) {
      _pending = widget.service.watch(widget.userId);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<PendingReport>>(
        stream: _pending,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                  'No se pudieron consultar los envíos guardados en este teléfono.'),
            );
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) return const SizedBox.shrink();
          return Card(
            child: ExpansionTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: Text(items.length == 1
                  ? '1 reporte pendiente de envío'
                  : '${items.length} reportes pendientes de envío'),
              subtitle: const Text('Guardados en este teléfono.'),
              children: [
                for (final item in items)
                  ListTile(
                    title: Text(item.fields['title'] ?? 'Reporte'),
                    subtitle: Text(item.blocked
                        ? 'No se pudo completar el envío. La copia sigue guardada.'
                        : item.reportConfirmed
                            ? 'Reporte enviado. Fotografía pendiente.'
                            : 'Se enviará cuando tengas conexión y abras la app.'),
                  ),
                TextButton(
                  onPressed: _retrying
                      ? null
                      : () async {
                          setState(() => _retrying = true);
                          try {
                            await widget.service
                                .processPending(retryBlocked: true);
                          } catch (_) {
                            // Local read errors remain visible in the stream.
                          } finally {
                            if (mounted) setState(() => _retrying = false);
                          }
                        },
                  child: Text(_retrying ? 'Reintentando…' : 'Reintentar'),
                ),
              ],
            ),
          );
        },
      );
}
