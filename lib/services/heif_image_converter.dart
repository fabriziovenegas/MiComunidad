import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

/// HEIF is an input format only. Upload queues and Firebase still receive JPEG.
class HeifImageConverter {
  HeifImageConverter._();

  static const extensions = ['heic', 'heif'];
  static const channel = MethodChannel('micomunidad/image_conversion');

  static Future<PlatformFile> toJpeg(PlatformFile source,
      {required int maxBytes}) async {
    try {
      final bytes = await channel.invokeMethod<Uint8List>('heifToJpeg', {
        'path': source.path,
        'bytes': source.bytes,
        'maxBytes': maxBytes,
      });
      if (bytes == null ||
          bytes.length < 4 ||
          bytes[0] != 0xff ||
          bytes[1] != 0xd8 ||
          bytes[bytes.length - 2] != 0xff ||
          bytes.last != 0xd9) {
        throw const HeifConversionException(
            'No se pudo convertir la fotografía. Selecciona otra imagen o una copia en JPG.');
      }
      if (bytes.length > maxBytes) {
        throw HeifConversionException(
            'La fotografía convertida no puede superar ${maxBytes ~/ (1024 * 1024)} MB.');
      }
      final separator = source.name.lastIndexOf('.');
      final base = separator > 0 ? source.name.substring(0, separator) : 'foto';
      return PlatformFile(name: '$base.jpg', size: bytes.length, bytes: bytes);
    } on MissingPluginException {
      throw const HeifConversionException(
          'Este dispositivo no permite convertir HEIC/HEIF. Selecciona una copia en JPG.');
    } on PlatformException catch (error) {
      throw HeifConversionException(switch (error.code) {
        'unsupported_device' =>
          'Este dispositivo no permite convertir HEIC/HEIF. Selecciona una copia en JPG.',
        'too_large' =>
          'La fotografía no puede superar ${maxBytes ~/ (1024 * 1024)} MB.',
        _ =>
          'No se pudo convertir la fotografía. Selecciona otra imagen o una copia en JPG.',
      });
    }
  }
}

class HeifConversionException implements Exception {
  const HeifConversionException(this.message);
  final String message;
}
