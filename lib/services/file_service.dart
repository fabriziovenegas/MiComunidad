import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'heif_image_converter.dart';

class SelectedUpload {
  const SelectedUpload(this.file);
  final PlatformFile file;
  String get name => file.name;
  int get size => file.size;
}

class UploadedFile {
  const UploadedFile({required this.url, required this.storagePath});

  final String url;
  final String storagePath;
}

class FileService {
  FileService._();

  static const int maxImageBytes = 10 * 1024 * 1024;
  static const int maxDocumentBytes = 5 * 1024 * 1024;
  static const imageExtensions = ['jpg', 'jpeg', 'png', 'webp'];
  static const documentExtensions = [...imageExtensions, 'pdf'];
  // Only selectors accept HEIF. Durable queues and uploads accept JPEG output.
  static const selectableImageExtensions = [
    ...imageExtensions,
    ...HeifImageConverter.extensions
  ];
  static const selectableDocumentExtensions = [
    ...selectableImageExtensions,
    'pdf'
  ];

  static String extensionOf(String name) => name.split('.').last.toLowerCase();
  static String contentTypeForName(String name) => switch (extensionOf(name)) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        'pdf' => 'application/pdf',
        _ => throw const FileUploadException(
            'El formato del archivo no es compatible.'),
      };

  static void validateFileHeader(String name, List<int> bytes) {
    bool startsWith(List<int> signature, [int offset = 0]) {
      if (bytes.length < offset + signature.length) return false;
      for (var index = 0; index < signature.length; index++) {
        if (bytes[offset + index] != signature[index]) return false;
      }
      return true;
    }

    final valid = switch (contentTypeForName(name)) {
      'image/jpeg' => startsWith([0xff, 0xd8, 0xff]),
      'image/png' => startsWith([137, 80, 78, 71, 13, 10, 26, 10]),
      'image/webp' =>
        startsWith([82, 73, 70, 70]) && startsWith([87, 69, 66, 80], 8),
      'application/pdf' => startsWith([37, 80, 68, 70, 45]),
      _ => false,
    };
    if (!valid) {
      throw const FileUploadException(
          'La extensión del archivo no coincide con su formato real.');
    }
  }

  static Future<void> validateSelectedFormat(SelectedUpload selected) async {
    final bytes = selected.file.bytes;
    if (bytes != null) {
      validateFileHeader(selected.name, bytes.take(16).toList());
      return;
    }
    final path = selected.file.path;
    if (path == null) {
      throw const FileUploadException(
          'No se pudo leer el archivo seleccionado.');
    }
    await validateLocalFileFormat(selected.name, path);
  }

  static Future<void> validateLocalFileFormat(String name, String path) async {
    try {
      final file = await File(path).open();
      try {
        validateFileHeader(name, await file.read(16));
      } finally {
        await file.close();
      }
    } on FileSystemException {
      throw const FileUploadException(
          'No se pudo leer el archivo seleccionado.');
    }
  }

  static Future<SelectedUpload?> pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: selectableImageExtensions,
      allowMultiple: false,
      withData: false,
    );
    if (result == null) return null;
    return preparePhoto(result.files.single);
  }

  static Future<SelectedUpload> preparePhoto(PlatformFile file) async {
    final selected = SelectedUpload(file);
    if (!selectableImageExtensions.contains(extensionOf(selected.name))) {
      throw const FileUploadException(
          'Selecciona una imagen JPG, JPEG, PNG, WEBP, HEIC o HEIF.');
    }
    if (selected.size > maxImageBytes) {
      throw FileUploadException(
          'La imagen no puede superar ${maxImageBytes ~/ (1024 * 1024)} MB.');
    }
    return _prepareImage(selected, maxImageBytes);
  }

  static Future<SelectedUpload?> pickIdentityDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: selectableDocumentExtensions,
      allowMultiple: false,
      withData: false,
    );
    if (result == null) return null;
    return prepareIdentityDocument(result.files.single);
  }

  // Shared only by the identity-document file, camera and gallery selectors.
  // Other modules keep their existing formats and size limits.
  static Future<SelectedUpload> prepareIdentityDocument(
      PlatformFile file) async {
    final selected = SelectedUpload(file);
    if (!selectableDocumentExtensions.contains(extensionOf(selected.name))) {
      throw const FileUploadException(
          'Selecciona un archivo JPG, JPEG, PNG, WEBP, HEIC, HEIF o PDF.');
    }
    if (selected.size > maxDocumentBytes) {
      throw FileUploadException(
          'El archivo no puede superar ${maxDocumentBytes ~/ (1024 * 1024)} MB.');
    }
    return _prepareImage(selected, maxDocumentBytes);
  }

  static Future<SelectedUpload> _prepareImage(
      SelectedUpload selected, int maxBytes) async {
    if (!HeifImageConverter.extensions.contains(extensionOf(selected.name))) {
      await validateSelectedFormat(selected);
      return selected;
    }
    try {
      final converted = SelectedUpload(
          await HeifImageConverter.toJpeg(selected.file, maxBytes: maxBytes));
      await validateSelectedFormat(converted);
      return converted;
    } on HeifConversionException catch (error) {
      throw FileUploadException(error.message);
    }
  }

  static Future<UploadedFile> upload({
    required SelectedUpload selected,
    required String folder,
    required String uploadedBy,
  }) async {
    await validateSelectedFormat(selected);
    final contentType = contentTypeForName(selected.name);
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    final safeName = selected.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final reference = FirebaseStorage.instance.ref(
      '$folder/${DateTime.now().millisecondsSinceEpoch}_$safeName',
    );
    final metadata = SettableMetadata(
      contentType: contentType,
      customMetadata: {'uploadedBy': uploadedBy},
    );
    if (selected.file.bytes != null) {
      await reference.putData(selected.file.bytes!, metadata);
    } else if (selected.file.path != null) {
      await reference.putFile(File(selected.file.path!), metadata);
    } else {
      throw const FileUploadException(
          'No se pudo leer el archivo seleccionado.');
    }
    return UploadedFile(
      url: 'gs://${reference.bucket}/${reference.fullPath}',
      storagePath: reference.fullPath,
    );
  }

  static Future<void> delete({String? storagePath, String? downloadUrl}) async {
    if (storagePath != null && storagePath.isNotEmpty) {
      await FirebaseStorage.instance.ref(storagePath).delete();
      return;
    }
    if (downloadUrl != null && downloadUrl.isNotEmpty) {
      await FirebaseStorage.instance.refFromURL(downloadUrl).delete();
    }
  }

  static Future<List<String>> listFilesRecursively(String folder) async {
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    final paths = <String>[];

    Future<void> collect(Reference reference) async {
      final result = await reference.listAll();
      paths.addAll(result.items.map((item) => item.fullPath));
      for (final prefix in result.prefixes) {
        await collect(prefix);
      }
    }

    await collect(FirebaseStorage.instance.ref(folder));
    return paths;
  }
}

class FileUploadException implements Exception {
  const FileUploadException(this.message);
  final String message;
  @override
  String toString() => message;
}
