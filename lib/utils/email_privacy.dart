/// Defensive UI masking; the backend applies the same policy independently.
String maskPublicEmail(Object? value) {
  final email = value is String ? value.trim() : '';
  if (RegExp(r'^[^@\s*]{0,2}\*{4}@\*{3}\.[a-z]{2,24}$', caseSensitive: false)
      .hasMatch(email)) {
    return email;
  }
  if (email.length > 320 ||
      !RegExp(r'^[^@\s]+@[^@\s]+\.[a-z]{2,63}$', caseSensitive: false)
          .hasMatch(email)) {
    return '';
  }
  final parts = email.split('@');
  final local = parts.first;
  if (parts.last.contains('*')) return '';
  final domain = parts.last.toLowerCase();
  if (local.contains('*')) {
    return RegExp(r'^[^@\s*]{0,2}\*{3,}[^@\s*]?$', unicode: true)
            .hasMatch(local)
        ? '$local@$domain'
        : '****@$domain';
  }
  final characters = local.runes.map(String.fromCharCode).toList();
  if (characters.length <= 3) return '****@$domain';
  if (characters.length <= 5) {
    return '${characters.first}${'*' * (characters.length - 1)}@$domain';
  }
  return '${characters.take(2).join()}${'*' * (characters.length - 3)}${characters.last}@$domain';
}
