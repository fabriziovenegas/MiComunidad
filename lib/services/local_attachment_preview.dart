import 'dart:io';
import 'package:flutter/services.dart';
import 'file_service.dart';

/// Reads the selected local file only. Never uploads or reads Firebase.
class LocalAttachmentPreview {
  LocalAttachmentPreview._();

  static const channel = MethodChannel('micomunidad/private_files');

  static Future<Uint8List> read(SelectedUpload selected) async {
    FileService.contentTypeForName(selected.name);
    if (selected.size > FileService.maxDocumentBytes) {
      throw const FileUploadException('El archivo no puede superar 5 MB.');
    }
    Uint8List bytes;
    if (selected.file.bytes != null) {
      bytes = selected.file.bytes!;
    } else {
      final path = selected.file.path;
      if (path == null) {
        throw const FileUploadException(
            'El archivo ya no está disponible. Vuelve a seleccionarlo.');
      }
      try {
        final file = await File(path).open();
        try {
          if (await file.length() > FileService.maxDocumentBytes) {
            throw const FileUploadException(
                'El archivo no puede superar 5 MB.');
          }
          bytes = await file.read(FileService.maxDocumentBytes + 1);
        } finally {
          await file.close();
        }
      } on FileSystemException {
        throw const FileUploadException(
            'El archivo ya no está disponible. Vuelve a seleccionarlo.');
      }
    }
    if (bytes.length > FileService.maxDocumentBytes) {
      throw const FileUploadException('El archivo no puede superar 5 MB.');
    }
    FileService.validateFileHeader(selected.name, bytes.take(16).toList());
    return bytes;
  }

  static Future<void> openPdf(SelectedUpload selected) async {
    if (FileService.contentTypeForName(selected.name) != 'application/pdf') {
      throw const FileUploadException('Selecciona un documento PDF válido.');
    }
    final bytes = await read(selected);
    try {
      // The existing Android handler grants temporary, read-only access to a
      // private cache copy. The original selection is never moved or deleted.
      await channel.invokeMethod<void>('openDocument', {
        'bytes': bytes,
        'contentType': 'application/pdf',
      });
    } on PlatformException catch (error) {
      throw FileUploadException(error.code == 'no-viewer'
          ? 'No hay una aplicación instalada para abrir archivos PDF.'
          : 'No se pudo abrir el PDF. Inténtalo nuevamente.');
    } on MissingPluginException {
      throw const FileUploadException(
          'Este dispositivo no dispone de un visor para abrir el PDF.');
    }
  }
}
