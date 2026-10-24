import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/utils/project_progress_input.dart';

void main() {
  final formatter = ProjectProgressInputFormatter();
  for (var value = 0; value <= 100; value++) {
    test('accepts and parses integer $value', () {
      final next = TextEditingValue(text: '$value');
      expect(formatter.formatEditUpdate(TextEditingValue.empty, next), next);
      expect(ProjectProgressInputFormatter.parse('$value'), value);
      expect(ProjectProgressInputFormatter.validate('$value'), isNull);
    });
  }

  for (final text in [
    '-1',
    '-5',
    '-100',
    '101',
    '999',
    '1.5',
    '0.5',
    '100.0',
    '1,5',
    '+5',
    '1e2',
    'NaN',
    'Infinity',
    'abc',
    ' 50 ',
    '50%',
    '5\n',
    '9999999999999999999999999999999999999999999999999999999999999'
  ]) {
    test('rejects the whole invalid entry $text without changing selection',
        () {
      const old = TextEditingValue(
          text: '50', selection: TextSelection.collapsed(offset: 1));
      final next = TextEditingValue(
          text: text, selection: TextSelection.collapsed(offset: text.length));
      expect(formatter.formatEditUpdate(old, next), old);
      expect(ProjectProgressInputFormatter.parse(text), isNull);
      expect(ProjectProgressInputFormatter.validate(text), isNotNull);
    });
  }

  test('allows clearing to retype but does not save an empty value as zero',
      () {
    expect(
        formatter.formatEditUpdate(
            const TextEditingValue(text: '50'), TextEditingValue.empty),
        TextEditingValue.empty);
    expect(ProjectProgressInputFormatter.validate(''), isNotNull);
    expect(ProjectProgressInputFormatter.validate(null), isNotNull);
  });

  test('preserves valid selection edits and parses leading zeros as an integer',
      () {
    const next = TextEditingValue(
        text: '050', selection: TextSelection.collapsed(offset: 1));
    expect(formatter.formatEditUpdate(const TextEditingValue(text: '50'), next),
        next);
    expect(ProjectProgressInputFormatter.parse('050'), 50);
  });
}
