import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Tipografía SJL Community Design System
/// Montserrat para headings, Inter para body
class AppTypography {
  // Headings - Montserrat Bold/SemiBold
  static const TextStyle headlineXl = TextStyle(
    fontFamily: 'Montserrat',
    fontSize: 40,
    fontWeight: FontWeight.w700,
    height: 48 / 40,
    letterSpacing: -0.02,
    color: AppColors.onSurface,
  );

  static const TextStyle headlineLg = TextStyle(
    fontFamily: 'Montserrat',
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 40 / 32,
    letterSpacing: -0.01,
    color: AppColors.onSurface,
  );

  static const TextStyle headlineLgMobile = TextStyle(
    fontFamily: 'Montserrat',
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 32 / 24,
    color: AppColors.onSurface,
  );

  static const TextStyle headlineMd = TextStyle(
    fontFamily: 'Montserrat',
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 32 / 24,
    color: AppColors.onSurface,
  );

  static const TextStyle headlineSm = TextStyle(
    fontFamily: 'Montserrat',
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 28 / 20,
    color: AppColors.onSurface,
  );

  // Body - Inter Normal
  static const TextStyle bodyLg = TextStyle(
    fontFamily: 'Inter',
    fontSize: 18,
    fontWeight: FontWeight.w400,
    height: 28 / 18,
    color: AppColors.onSurface,
  );

  static const TextStyle bodyMd = TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 24 / 16,
    color: AppColors.onSurface,
  );

  static const TextStyle bodySm = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 20 / 14,
    color: AppColors.onSurface,
  );

  // Labels - Inter Medium/SemiBold
  static const TextStyle labelMd = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 20 / 14,
    color: AppColors.onSurface,
  );

  static const TextStyle labelSm = TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 16 / 12,
    color: AppColors.onSurface,
  );

  // Variantes para diferentes estados
  static TextStyle bodyLgOnVariant(Color color) =>
      bodyLg.copyWith(color: color);
  static TextStyle bodyMdOnVariant(Color color) =>
      bodyMd.copyWith(color: color);
  static TextStyle bodySmOnVariant(Color color) =>
      bodySm.copyWith(color: color);

  static TextStyle labelMdOnVariant(Color color) =>
      labelMd.copyWith(color: color);
  static TextStyle labelSmOnVariant(Color color) =>
      labelSm.copyWith(color: color);
}
