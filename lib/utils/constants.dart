import 'package:flutter/material.dart';

// ============================================================================
// COLORES - PALETA DE DISEÑO
// ============================================================================

class AppColors {
  // Colores primarios
  static const Color primary = Color(0xFFD85A2E); // Terracota
  static const Color secondary = Color(0xFF8B7355); // Marrón cálido
  static const Color accent = Color(0xFFE8C547); // Dorado cálido
  static const Color background = Color(0xFFFAF8F3); // Crema suave
  static const Color surface = Color(0xFFFFFFFF); // Blanco

  // Texto
  static const Color textPrimary = Color(0xFF2C2416); // Marrón oscuro
  static const Color textSecondary = Color(0xFF6B6B6B); // Gris
  static const Color textLight = Color(0xFF9E9E9E); // Gris claro
  static const Color textDisabled = Color(0xFFBDBDBD); // Gris muy claro

  // Estados
  static const Color success = Color(0xFF6FA876); // Oliva
  static const Color error = Color(0xFFD84C31); // Rojo terracota
  static const Color warning = Color(0xFFF5A623); // Naranja
  static const Color info = Color(0xFF4A90E2); // Azul

  // Bordes
  static const Color borderLight = Color(0xFFE0D5C7); // Borde claro
  static const Color borderDark = Color(0xFF8B7355); // Borde oscuro
}

// ============================================================================
// ESPACIADO
// ============================================================================

class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
}

// ============================================================================
// TIPOGRAFÍA
// ============================================================================

class AppTypography {
  // Display (Títulos principales)
  static const TextStyle displayLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.bold,
    height: 1.2,
    color: AppColors.secondary,
    fontFamily: 'Inter',
  );

  static const TextStyle displayMedium = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    height: 1.2,
    color: AppColors.secondary,
    fontFamily: 'Inter',
  );

  // Headline (Títulos de secciones)
  static const TextStyle headlineLarge = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    height: 1.3,
    color: AppColors.textPrimary,
    fontFamily: 'Inter',
  );

  static const TextStyle headlineMedium = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    height: 1.3,
    color: AppColors.textPrimary,
    fontFamily: 'Inter',
  );

  // Body Large (Contenido principal)
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    height: 1.6,
    color: AppColors.textPrimary,
    fontFamily: 'Inter',
  );

  // Body (Texto general)
  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    height: 1.6,
    color: AppColors.textPrimary,
    fontFamily: 'Inter',
  );

  // Body Small (Labels, texto secundario)
  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    height: 1.5,
    color: AppColors.textSecondary,
    fontFamily: 'Inter',
  );

  // Caption (Fechas, información adicional)
  static const TextStyle caption = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.normal,
    height: 1.4,
    color: AppColors.textSecondary,
    fontFamily: 'Inter',
  );

  // Button Text
  static const TextStyle buttonText = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: Colors.white,
    fontFamily: 'Inter',
    letterSpacing: 0.3,
  );

  static const TextStyle buttonSecondaryText = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: AppColors.primary,
    fontFamily: 'Inter',
    letterSpacing: 0.3,
  );
}

// ============================================================================
// BORDES RADIUS
// ============================================================================

class AppBorderRadius {
  static const double small = 4.0;
  static const double medium = 8.0;
  static const double large = 12.0;
}

// ============================================================================
// SOMBRAS
// ============================================================================

class AppShadows {
  static const BoxShadow small = BoxShadow(
    color: Color(0x0D000000),
    blurRadius: 4,
    offset: Offset(0, 2),
  );

  static const BoxShadow medium = BoxShadow(
    color: Color(0x14000000),
    blurRadius: 8,
    offset: Offset(0, 4),
  );

  static const BoxShadow large = BoxShadow(
    color: Color(0x21000000),
    blurRadius: 16,
    offset: Offset(0, 8),
  );
}

// ============================================================================
// ANIMACIONES
// ============================================================================

class AppDurations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
}

class AppCurves {
  static const Curve smooth = Curves.easeInOutCubic;
  static const Curve snappy = Curves.easeOutCubic;
}

// ============================================================================
// TAMAÑOS DE PANTALLA
// ============================================================================

class AppSizes {
  static const double mobileMax = 480;
  static const double tabletMin = 480;
  static const double tabletMax = 768;
  static const double desktopMin = 768;
}

// ============================================================================
// RUTAS DE NAVEGACIÓN
// ============================================================================

class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String home = '/home';
  static const String community = '/community';
  static const String projects = '/projects';
  static const String projectDetail = '/projects/:id';
  static const String createProject = '/projects/create';
  static const String editProject = '/projects/:id/edit';
  static const String issues = '/issues';
  static const String issueDetail = '/issues/:id';
  static const String registerIssue = '/issues/register';
  static const String agenda = '/agenda';
  static const String announcements = '/announcements';
  static const String admin = '/admin';
  static const String history = '/history';
  static const String settings = '/settings';
}

// ============================================================================
// TEXTOS Y MENSAJES
// ============================================================================

class AppStrings {
  // Autenticación
  static const String loginTitle = 'MiComunidad';
  static const String loginSubtitle = 'Ingresa tu cuenta';
  static const String emailLabel = 'Correo electrónico';
  static const String passwordLabel = 'Contraseña';
  static const String loginButton = 'Iniciar Sesión';
  static const String forgotPassword = '¿Olvidaste tu contraseña?';
  static const String noAccount = '¿No tienes cuenta?';
  static const String createAccount = 'Crear una Cuenta';
  static const String signupTitle = 'Crear Cuenta';
  static const String signupSubtitle = 'Únete a la comunidad';
  static const String nameLabel = 'Nombre completo';
  static const String phoneLabel = 'Teléfono';
  static const String signupButton = 'Crear Cuenta';
  static const String haveAccount = '¿Ya tienes cuenta?';
  static const String logIn = 'Inicia sesión';

  // Validaciones
  static const String emailRequired = 'El email es requerido';
  static const String emailInvalid = 'Ingresa un email válido';
  static const String passwordRequired = 'La contraseña es requerida';
  static const String passwordTooShort = 'Mínimo 6 caracteres';
  static const String nameRequired = 'El nombre es requerido';
  static const String fieldRequired = 'Este campo es requerido';

  // Navegación
  static const String community = 'COMUNIDAD';
  static const String projects = 'PROYECTOS';
  static const String issues = 'PROBLEMAS';
  static const String agenda = 'AGENDA';
  static const String announcements = 'ANUNCIOS';
  static const String admin = 'ADMIN';

  // Acciones
  static const String save = 'Guardar';
  static const String cancel = 'Cancelar';
  static const String delete = 'Eliminar';
  static const String edit = 'Editar';
  static const String approve = 'Aprobar';
  static const String reject = 'Rechazar';
  static const String register = 'Registrar';
  static const String create = 'Crear';
  static const String submit = 'Enviar';
  static const String logout = 'Cerrar Sesión';

  // Mensajes de éxito
  static const String successLogin = 'Sesión iniciada exitosamente';
  static const String successSignup =
      'Cuenta creada! Espera aprobación del admin';
  static const String successSave = 'Guardado exitosamente';
  static const String successCreate = 'Creado exitosamente';
  static const String successDelete = 'Eliminado exitosamente';

  // Mensajes de error
  static const String errorLogin = 'Email o contraseña incorrectos';
  static const String errorNetwork = 'Error de conexión. Intenta de nuevo';
  static const String errorUnknown = 'Ocurrió un error. Intenta de nuevo';
}

// ============================================================================
// DURACIONES PARA DELAYS
// ============================================================================

class AppDelays {
  static const int toastDuration = 3000; // ms
  static const int navigationDelay = 300; // ms
}
