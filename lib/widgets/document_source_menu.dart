import 'package:flutter/material.dart';
import '../services/access_request_document_picker.dart';
import '../services/file_service.dart';
import 'upload_picker.dart';

Future<AccessDocumentSource?> showDocumentSourceMenu(BuildContext context) =>
    showModalBottomSheet<AccessDocumentSource>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final option in const [
            (
              AccessDocumentSource.camera,
              Icons.photo_camera_outlined,
              'Tomar foto'
            ),
            (
              AccessDocumentSource.gallery,
              Icons.photo_library_outlined,
              'Elegir de galería'
            ),
            (
              AccessDocumentSource.file,
              Icons.attach_file,
              'Seleccionar archivo'
            ),
          ])
            ListTile(
              leading: Icon(option.$2),
              title: Text(option.$3),
              onTap: () => Navigator.pop(sheet, option.$1),
            ),
        ]),
      ),
    );

/// All sources use the existing document formats, conversion and 5 MB limit.
Future<SelectedUpload?> pickDocumentWithMenu(BuildContext context,
    {Future<SelectedUpload?> Function(AccessDocumentSource)? pick}) async {
  final source = await showDocumentSourceMenu(context);
  if (source == null || !context.mounted) return null;
  return pickUploadWithFeedback(context, () async {
    final selected = await (pick ?? AccessRequestDocumentPicker().pick)(source);
    return selected == null
        ? null
        : FileService.prepareIdentityDocument(selected.file);
  });
}
