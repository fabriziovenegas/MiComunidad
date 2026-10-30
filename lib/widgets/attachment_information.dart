import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

WidgetBuilder attachmentInformationBuilder(String collection, String documentId,
        String kind, String attachmentId, Map<String, dynamic> data) =>
    (_) => AttachmentInformationDialog(
          name: data['name'] is String ? data['name'] as String : '',
          createdAt: data['createdAt'],
          loadName: () async {
            final result = await FirebaseFunctions.instanceFor(
                    region: 'southamerica-east1')
                .httpsCallable('getAttachmentUploaderName')
                .call<Map<String, dynamic>>({
              'collection': collection,
              'documentId': documentId,
              'kind': kind,
              'attachmentId': attachmentId,
            });
            return result.data['name'] as String?;
          },
        );

class AttachmentInformationDialog extends StatefulWidget {
  const AttachmentInformationDialog(
      {super.key,
      required this.name,
      required this.createdAt,
      required this.loadName});
  final String name;
  final Object? createdAt;
  final Future<String?> Function() loadName;
  @override
  State<AttachmentInformationDialog> createState() =>
      _AttachmentInformationDialogState();
}

class _AttachmentInformationDialogState
    extends State<AttachmentInformationDialog> {
  late final Future<String?> _name;
  @override
  void initState() {
    super.initState();
    _name = Future.sync(widget.loadName).then((v) => v, onError: (_) => null);
  }

  @override
  Widget build(BuildContext context) {
    final date = widget.createdAt is Timestamp
        ? (widget.createdAt as Timestamp).toDate().toLocal()
        : null;
    return AlertDialog(
      title: const Text('Información del archivo'),
      content: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            if (widget.name.trim().isNotEmpty) ...[
              Text(widget.name),
              const SizedBox(height: 16)
            ],
            const Text('Subido por',
                style: TextStyle(fontWeight: FontWeight.w600)),
            FutureBuilder<String?>(
                future: _name,
                builder: (context, snapshot) => Text(
                    snapshot.connectionState == ConnectionState.waiting
                        ? 'Consultando…'
                        : (snapshot.data?.trim().isNotEmpty == true
                            ? snapshot.data!.trim()
                            : 'No disponible'))),
            const SizedBox(height: 16),
            const Text('Fecha de subida',
                style: TextStyle(fontWeight: FontWeight.w600)),
            Text(date == null
                ? 'No disponible'
                : DateFormat('dd/MM/yyyy · HH:mm').format(date)),
          ])),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'))
      ],
    );
  }
}
