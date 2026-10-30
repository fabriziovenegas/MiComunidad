import 'package:flutter/material.dart';
import 'expandable_description.dart';

class ContentCommentTile extends StatelessWidget {
  const ContentCommentTile(
      {super.key,
      required this.author,
      required this.text,
      this.date,
      this.onDelete,
      this.onEdit});
  final String author, text;
  final String? date;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.only(top: 12, bottom: 12),
        decoration: const BoxDecoration(
            border: Border(
                bottom: BorderSide(color: Color(0xFFD8E4DC), width: 0.7))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CircleAvatar(child: Icon(Icons.person)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(author,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        if (date != null) ...[
                          const SizedBox(height: 2),
                          Text(date!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                        ],
                      ],
                    ),
                  ),
                  if (onDelete != null || onEdit != null)
                    PopupMenuButton<String>(
                      tooltip: 'Opciones del comentario',
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) {
                        if (value == 'edit') onEdit?.call();
                        if (value == 'delete') onDelete?.call();
                      },
                      itemBuilder: (context) => [
                        if (onEdit != null)
                          const PopupMenuItem<String>(
                              value: 'edit',
                              child: Row(children: [
                                Icon(Icons.edit_outlined, size: 20),
                                SizedBox(width: 10),
                                Flexible(child: Text('Editar comentario'))
                              ])),
                        if (onDelete != null)
                          PopupMenuItem<String>(
                            value: 'delete',
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.delete_outline,
                                  size: 20,
                                  color: Theme.of(context).colorScheme.error),
                              const SizedBox(width: 10),
                              Flexible(
                                  child: Text('Eliminar comentario',
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error))),
                            ]),
                          ),
                      ],
                    ),
                ]),
                const SizedBox(height: 2),
                ExpandableDescription(
                    text: text,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ])),
        ]),
      );
}
