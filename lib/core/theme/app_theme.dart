import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/app_colors.dart';

class AppTheme {
  AppTheme._();
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      surface: AppColors.surface,
      error: AppColors.error,
    );
    final textTheme = GoogleFonts.interTextTheme().copyWith(
      headlineLarge: GoogleFonts.montserrat(fontWeight: FontWeight.w700),
      headlineMedium: GoogleFonts.montserrat(fontWeight: FontWeight.w700),
      headlineSmall: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
      titleLarge: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.surface,
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.onSurface),
      cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.outlineVariant))),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceContainerLow,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.outlineVariant))),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)))),
      navigationBarTheme: NavigationBarThemeData(
          indicatorColor: AppColors.primaryContainer,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          labelTextStyle:
              WidgetStatePropertyAll(GoogleFonts.inter(fontSize: 11))),
    );
  }
}
