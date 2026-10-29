import 'text_encoding.dart';

String requestRejectionReason(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return 'No se indicó un motivo de rechazo.';
  }
  return readableText(value).trim();
}
