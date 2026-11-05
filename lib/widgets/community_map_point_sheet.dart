import 'package:flutter/material.dart';
import 'online_action_dialog.dart';

class CommunityMapPointSheet extends StatefulWidget {
  const CommunityMapPointSheet(
      {super.key,
      required this.title,
      required this.description,
      this.onDelete,
      this.actionKey,
      this.isOffline});
  final String title;
  final String description;
  final Future<void> Function()? onDelete;
  final String? actionKey;
  final Future<bool> Function()? isOffline;
  @override
  State<CommunityMapPointSheet> createState() => _CommunityMapPointSheetState();
}

class _CommunityMapPointSheetState extends State<CommunityMapPointSheet> {
  bool _busy = false;
  Future<void> _delete() async {
    if (_busy || widget.onDelete == null) return;
    setState(() => _busy = true);
    try {
      final deleted = await showOnlineActionConfirmation(context,
          actionKey: widget.actionKey ?? 'delete-map-point:${widget.title}',
          title: 'Eliminar punto',
          question:
              '¿Deseas eliminar «${widget.title}» del mapa? Esta acción no se puede deshacer.',
          confirmLabel: 'Eliminar',
          successMessage: 'Punto eliminado.',
          slowMessage:
              'La eliminación del punto del mapa está tardando. Verifica tu conexión.',
          isOffline: widget.isOffline,
          action: widget.onDelete!);
      if (deleted == true && mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                20, 0, 20, 24 + MediaQuery.paddingOf(context).bottom),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      style: Theme.of(context).textTheme.titleLarge),
                  if (widget.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(widget.description)
                  ],
                  if (widget.onDelete != null) ...[
                    const SizedBox(height: 24),
                    SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                            onPressed: _busy ? null : _delete,
                            icon: const Icon(Icons.delete_outline),
                            style: OutlinedButton.styleFrom(
                                foregroundColor:
                                    Theme.of(context).colorScheme.error),
                            label:
                                Text(_busy ? 'Eliminando…' : 'Eliminar punto')))
                  ],
                ])),
      );
}
