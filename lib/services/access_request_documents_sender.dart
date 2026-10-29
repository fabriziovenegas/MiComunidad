import 'file_service.dart';

/// The application is submitted only after every selected file is uploaded.
/// Upload failures leave the form and its selection available for retry.
Future<T> sendAccessRequestDocuments<T>({
  required List<SelectedUpload> documents,
  required Future<UploadedFile> Function(SelectedUpload file) upload,
  required Future<T> Function(List<UploadedFile> files) submit,
}) async {
  final selected = List<SelectedUpload>.unmodifiable(documents);
  if (selected.isEmpty || selected.length > 3) {
    throw const FileUploadException('Adjunta entre 1 y 3 documentos.');
  }
  // Check every input before starting a batch; retain existing HEIF conversion.
  for (final file in selected) {
    if (file.size <= 0 || file.size > FileService.maxDocumentBytes) {
      throw const FileUploadException('El archivo no puede superar 5 MB.');
    }
    await FileService.validateSelectedFormat(file);
  }
  final uploaded = <UploadedFile>[];
  for (final file in selected) {
    uploaded.add(await upload(file));
  }
  return submit(List<UploadedFile>.unmodifiable(uploaded));
}
