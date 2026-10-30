import 'package:flutter/material.dart';
import '../services/photo_picker.dart';
import '../services/file_service.dart';
import 'upload_error_notice.dart';

Future<PhotoSelection> pickPhotosWithMenu(BuildContext context,
    {bool multiple = true,
    Future<PhotoSelection> Function(PhotoSource, bool)? pick}) async {
  final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final option in [
              (PhotoSource.camera, Icons.photo_camera_outlined, 'Tomar foto'),
              (
                PhotoSource.gallery,
                Icons.photo_library_outlined,
                'Elegir de galería'
              ),
              (
                PhotoSource.files,
                Icons.folder_open_outlined,
                'Seleccionar archivos'
              ),
            ])
              ListTile(
                  leading: Icon(option.$2),
                  title: Text(option.$3),
                  onTap: () => Navigator.pop(sheet, option.$1)),
          ])));
  if (source == null || !context.mounted) return const PhotoSelection([]);
  try {
    final result = await (pick?.call(source, multiple) ??
        PhotoPicker().pick(source, multiple: multiple));
    if (!context.mounted) return const PhotoSelection([]);
    if (result.errors.isNotEmpty) {
      showUploadError(context, result.errors.join('\n'));
    }
    return result;
  } on FileUploadException catch (error) {
    if (context.mounted) showUploadError(context, error.message);
  } catch (_) {
    if (context.mounted) {
      showUploadError(context, 'No se pudo seleccionar la fotografía.');
    }
  }
  return const PhotoSelection([]);
}
