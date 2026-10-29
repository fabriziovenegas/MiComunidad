import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'file_service.dart';

enum AccessDocumentSource { camera, gallery, file }

class AccessRequestDocumentPicker {
  AccessRequestDocumentPicker({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<SelectedUpload?> pick(AccessDocumentSource source) async {
    if (source == AccessDocumentSource.file) {
      return FileService.pickIdentityDocument();
    }
    try {
      final image = await _picker.pickImage(
        source: source == AccessDocumentSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (image == null) return null;
      return _prepare(image);
    } on PlatformException catch (error) {
      throw FileUploadException(switch (error.code) {
        'camera_access_denied' ||
        'photo_access_denied' =>
          'Permite el acceso a la cámara o a las fotos desde los ajustes del teléfono.',
        'no_available_camera' => 'No se encontró una cámara disponible.',
        _ => 'No se pudo seleccionar la fotografía. Inténtalo nuevamente.',
      });
    }
  }

  Future<List<SelectedUpload>> recoverLostImages() async {
    final recovered = await _picker.retrieveLostData();
    if (recovered.exception != null) {
      throw const FileUploadException(
          'No se pudo recuperar la fotografía seleccionada. Inténtalo nuevamente.');
    }
    final images = recovered.files ?? const <XFile>[];
    final result = <SelectedUpload>[];
    for (final image in images.take(3)) {
      result.add(await _prepare(image));
    }
    return result;
  }

  Future<SelectedUpload> _prepare(XFile image) async {
    final size = await image.length();
    final name = image.name.replaceAll('\\', '/').split('/').last;
    return FileService.prepareIdentityDocument(
        PlatformFile(name: name, size: size, path: image.path));
  }
}
