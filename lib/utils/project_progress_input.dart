import 'package:flutter/services.dart';

/// Rejects an invalid edit as a whole, rather than turning -5 or 1.5 into 5/15.
class ProjectProgressInputFormatter extends TextInputFormatter {
  static final _digits = RegExp(r'^[0-9]+$');

  static int? parse(String? text) {
    if (text == null || !_digits.hasMatch(text)) return null;
    final value = int.tryParse(text);
    return value != null && value >= 0 && value <= 100 ? value : null;
  }

  static String? validate(String? text) =>
      parse(text) == null ? 'Ingresa un número entero entre 0 y 100.' : null;

  @override
  TextEditingValue formatEditUpdate(
          TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.text.isEmpty || parse(newValue.text) != null
          ? newValue
          : oldValue;
}
