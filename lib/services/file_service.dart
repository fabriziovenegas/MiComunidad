import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

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

  static Future<SelectedUpload?> pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png'],
      allowMultiple: false,
      withData: false,
    );
    if (result == null) return null;
    final selected = SelectedUpload(result.files.single);
    if (selected.size > maxImageBytes) {
      throw FileUploadException(
          'La imagen no puede superar ${maxImageBytes ~/ (1024 * 1024)} MB.');
    }
    return selected;
  }

  static Future<SelectedUpload?> pickIdentityDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
      allowMultiple: false,
      withData: false,
    );
    if (result == null) return null;
    final selected = SelectedUpload(result.files.single);
    if (selected.size > maxDocumentBytes) {
      throw FileUploadException(
          'El archivo no puede superar ${maxDocumentBytes ~/ (1024 * 1024)} MB.');
    }
    return selected;
  }

  static Future<UploadedFile> upload({
    required SelectedUpload selected,
    required String folder,
    required String uploadedBy,
  }) async {
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    final safeName = selected.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final reference = FirebaseStorage.instance.ref(
      '$folder/${DateTime.now().millisecondsSinceEpoch}_$safeName',
    );
    final extension = safeName.split('.').last.toLowerCase();
    final contentType = extension == 'pdf'
        ? 'application/pdf'
        : extension == 'png'
            ? 'image/png'
            : 'image/jpeg';
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
      url: await reference.getDownloadURL(),
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
