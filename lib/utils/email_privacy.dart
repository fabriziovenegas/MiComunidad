/// Defensive UI masking, including responses from older server versions.
String maskPublicEmail(Object? value) {
  final email = value is String ? value.trim() : '';
  if (RegExp(r'^[^@\s*]{0,2}\*{4}@\*{3}\.[a-z]{2,24}$', caseSensitive: false)
      .hasMatch(email)) {
    return email;
  }
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[a-z]{2,24}$', caseSensitive: false)
      .hasMatch(email)) {
    return '';
  }
  final parts = email.split('@');
  final local = parts.first;
  final prefixLength = local.length > 2 ? 2 : local.length - 1;
  final prefix = local.substring(0, prefixLength);
  final suffix = parts.last.split('.').last.toLowerCase();
  return '$prefix****@***.$suffix';
}
