class Validators {
  // Validar email
  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'El email es requerido';
    }

    final emailRegex =
        RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');

    if (!emailRegex.hasMatch(value)) {
      return 'Ingresa un email válido';
    }

    return null;
  }

  // Validar contraseña
  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'La contraseña es requerida';
    }

    if (value.length < 6) {
      return 'Mínimo 6 caracteres';
    }

    return null;
  }

  // Validar nombre
  static String? validateName(String? value) {
    if (value == null || value.isEmpty) {
      return 'El nombre es requerido';
    }

    if (value.length < 2) {
      return 'El nombre debe tener al menos 2 caracteres';
    }

    return null;
  }

  // Validar campo requerido
  static String? validateRequired(String? value) {
    if (value == null || value.isEmpty) {
      return 'Este campo es requerido';
    }
    return null;
  }

  // Validar descripción
  static String? validateDescription(String? value) {
    if (value == null || value.isEmpty) {
      return 'La descripción es requerida';
    }

    if (value.length < 10) {
      return 'La descripción debe tener al menos 10 caracteres';
    }

    if (value.length > 500) {
      return 'La descripción no puede exceder 500 caracteres';
    }

    return null;
  }

  // Validar porcentaje (0-100)
  static String? validatePercent(String? value) {
    if (value == null || value.isEmpty) {
      return 'El valor es requerido';
    }

    try {
      final percent = int.parse(value);
      if (percent < 0 || percent > 100) {
        return 'Debe estar entre 0 y 100';
      }
      return null;
    } catch (e) {
      return 'Ingresa un número válido';
    }
  }

  // Validar teléfono
  static String? validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Opcional
    }

    final phoneRegex = RegExp(r'^[\d\s\+\-\(\)]{7,}$');
    if (!phoneRegex.hasMatch(value)) {
      return 'Ingresa un teléfono válido';
    }

    return null;
  }

  // Validar fecha inicio < fecha fin
  static String? validateDateRange(DateTime? startDate, DateTime? endDate) {
    if (startDate == null || endDate == null) {
      return 'Las fechas son requeridas';
    }

    if (endDate.isBefore(startDate)) {
      return 'La fecha fin no puede ser anterior a la fecha inicio';
    }

    return null;
  }

  // Validar presupuesto
  static String? validateBudget(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Opcional
    }

    try {
      final budget = double.parse(value);
      if (budget < 0) {
        return 'El presupuesto no puede ser negativo';
      }
      return null;
    } catch (e) {
      return 'Ingresa un número válido';
    }
  }
}
