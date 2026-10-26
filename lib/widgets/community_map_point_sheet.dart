import 'package:flutter/material.dart';
import 'upload_error_notice.dart';

class CommunityMapPointSheet extends StatefulWidget {
  const CommunityMapPointSheet(
      {super.key,
      required this.title,
      required this.description,
      this.onDelete});
  final String title;
  final String description;
  final Future<void> Function()? onDelete;
  @override
  State<CommunityMapPointSheet> createState() => _CommunityMapPointSheetState();
}

class _CommunityMapPointSheetState extends State<CommunityMapPointSheet> {
  bool _busy = false;
  Future<void> _delete() async {
    if (_busy || widget.onDelete == null) return;
    // Reserve the action before opening confirmation to prevent stacked dialogs.
    setState(() => _busy = true);
    try {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Eliminar punto'),
                  content: Text(
                      '¿Deseas eliminar «${widget.title}» del mapa? Esta acción no se puede deshacer.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Eliminar'))
                  ]));
      if (confirmed != true || !mounted) return;
      await widget.onDelete!();
      if (!mounted) return;
      showSuccessNotice(context, 'Punto eliminado.');
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        showUploadError(
            context, 'No se pudo eliminar el punto. Inténtalo nuevamente.');
      }
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
