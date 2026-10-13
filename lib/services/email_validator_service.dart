/// Servicio de validación de emails
/// Solo permite emails de Gmail, Hotmail, Yahoo y Outlook
class EmailValidatorService {
  static const List<String> _allowedDomains = [
    'gmail.com',
    'hotmail.com',
    'outlook.com',
    'yahoo.com',
    'yahoo.es',
    'hotmail.es',
    'gmail.es',
  ];

  /// Validar si el email es permitido
  static bool isValidEmail(String email) {
    try {
      // Validar formato básico
      final regex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
      if (!regex.hasMatch(email)) {
        return false;
      }

      // Extraer dominio
      final domain = email.split('@').last.toLowerCase();

      // Verificar que el dominio esté permitido
      return _allowedDomains.contains(domain);
    } catch (e) {
      return false;
    }
  }

  /// Obtener el proveedor de email
  static String getEmailProvider(String email) {
    final domain = email.split('@').last.toLowerCase();

    if (domain.contains('gmail')) return 'Gmail';
    if (domain.contains('hotmail')) return 'Hotmail';
    if (domain.contains('outlook')) return 'Outlook';
    if (domain.contains('yahoo')) return 'Yahoo';

    return 'Desconocido';
  }

  /// Validar múltiples emails
  static bool areAllEmailsValid(List<String> emails) {
    return emails.every((email) => isValidEmail(email));
  }

  /// Obtener mensaje de error para email inválido
  static String getEmailErrorMessage(String email) {
    if (!email.contains('@')) {
      return 'El email debe contener una arroba (@)';
    }

    final domain = email.split('@').last.toLowerCase();

    if (!_allowedDomains.contains(domain)) {
      return 'Solo se permiten emails de Gmail, Hotmail, Yahoo u Outlook';
    }

    return 'El formato del email no es válido';
  }
}
