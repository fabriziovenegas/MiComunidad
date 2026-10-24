import 'package:flutter/material.dart';
import '../services/file_service.dart';
import 'upload_error_notice.dart';

/// Selection errors happen before uploading, so handle them at the picker too.
Future<SelectedUpload?> pickUploadWithFeedback(
  BuildContext context,
  Future<SelectedUpload?> Function() pick,
) async {
  String message;
  try {
    final selected = await pick();
    if (context.mounted && selected != null) dismissUploadError();
    return context.mounted ? selected : null;
  } on FileUploadException catch (error) {
    message = error.message;
  } catch (_) {
    message = 'No se pudo seleccionar el archivo. Inténtalo nuevamente.';
  }
  if (context.mounted) {
    showUploadError(context, message);
  }
  return null;
}
