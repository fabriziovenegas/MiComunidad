import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'file_service.dart';

enum PhotoSource { camera, gallery, files }

class PhotoSelection {
  const PhotoSelection(this.photos, {this.errors = const []});
  final List<SelectedUpload> photos;
  final List<String> errors;
}

/// Only photos: document selectors keep their own formats and 5 MB limit.
class PhotoPicker {
  PhotoPicker({ImagePicker? picker}) : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  Future<PhotoSelection> pick(PhotoSource source,
      {bool multiple = true}) async {
    try {
      List<PlatformFile> files;
      if (source == PhotoSource.files) {
        final result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: FileService.selectableImageExtensions,
            allowMultiple: multiple,
            withData: false);
        files = result?.files ?? [];
      } else {
        final List<XFile> images;
        if (source == PhotoSource.gallery && multiple) {
          images = await _picker.pickMultiImage(requestFullMetadata: false);
        } else {
          final image = await _picker.pickImage(
              source: source == PhotoSource.camera
                  ? ImageSource.camera
                  : ImageSource.gallery,
              requestFullMetadata: false);
          images = image == null ? [] : [image];
        }
        files = [];
        for (final image in images) {
          files.add(PlatformFile(
              name: image.name.replaceAll('\\', '/').split('/').last,
              size: await image.length(),
              path: image.path));
        }
      }
      final photos = <SelectedUpload>[];
      final errors = <String>[];
      final paths = <String>{};
      for (final file in multiple ? files : files.take(1)) {
        if (file.path != null && !paths.add(file.path!)) continue;
        try {
          photos.add(await FileService.preparePhoto(file));
        } on FileUploadException catch (error) {
          errors.add('${file.name}: ${error.message}');
        } catch (_) {
          errors.add('${file.name}: No se pudo leer la fotografía.');
        }
      }
      return PhotoSelection(photos, errors: errors);
    } on PlatformException catch (error) {
      throw FileUploadException(switch (error.code) {
        'camera_access_denied' ||
        'photo_access_denied' =>
          'Permite el acceso a la cámara o a las fotos desde los ajustes del teléfono.',
        'no_available_camera' => 'No se encontró una cámara disponible.',
        _ =>
          'No se pudieron seleccionar las fotografías. Inténtalo nuevamente.',
      });
    }
  }
}
