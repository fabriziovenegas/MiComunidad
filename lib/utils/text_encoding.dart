import 'dart:convert';

/// Repara textos históricos guardados como UTF-8 interpretado como Latin-1.
/// Los datos nuevos de Flutter se guardan directamente en Unicode.
String readableText(Object? value) {
  var text = value?.toString() ?? '';
  if (text.contains('Ã') || text.contains('Â') || text.contains('â')) {
    try {
      text = utf8.decode(latin1.encode(text));
    } on FormatException {
      // Conserva el original si la cadena no es reversible.
    }
  }
  const knownLostAccents = <String, String>{
    'Mar�a': 'María',
    'Garc�a': 'García',
    'Jos�': 'José',
    'L�pez': 'López',
    'Guti�rrez': 'Gutiérrez',
    'M�nica': 'Mónica',
    'tel�fono': 'teléfono',
    'direcci�n': 'dirección',
    'Direcci�n': 'Dirección',
    'descripci�n': 'descripción',
    'Descripci�n': 'Descripción',
    'revisi�n': 'revisión',
    'atenci�n': 'atención',
    'ubicaci�n': 'ubicación',
    'informaci�n': 'información',
    'Informaci�n': 'Información',
    'reuni�n': 'reunión',
    'participaci�n': 'participación',
    'Participaci�n': 'Participación',
    'M�s': 'Más',
    'a�os': 'años',
  };
  for (final entry in knownLostAccents.entries) {
    text = text.replaceAll(entry.key, entry.value);
  }
  return text.replaceAll('�', '');
}
