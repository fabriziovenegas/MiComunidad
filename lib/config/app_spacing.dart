import 'package:flutter/material.dart';

/// Espaciado SJL Community Design System
/// Basado en escala de 4px
class AppSpacing {
  // Valores base
  static const double base = 4;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 40;
  static const double containerMargin = 16;
  static const double gutter = 16;

  // Border radius
  static const double radiusSm = 4;
  static const double radiusMd = 8;
  static const double radiusLg = 12;
  static const double radiusXl = 16;
  static const double radiusXxl = 24;
  static const double radiusFull = 9999;

  // EdgeInsets - Simétricos
  static const EdgeInsets paddingXs = EdgeInsets.all(xs);
  static const EdgeInsets paddingSm = EdgeInsets.all(sm);
  static const EdgeInsets paddingMd = EdgeInsets.all(md);
  static const EdgeInsets paddingLg = EdgeInsets.all(lg);
  static const EdgeInsets paddingXl = EdgeInsets.all(xl);

  // EdgeInsets - Horizontales
  static const EdgeInsets paddingHorizontalXs =
      EdgeInsets.symmetric(horizontal: xs);
  static const EdgeInsets paddingHorizontalSm =
      EdgeInsets.symmetric(horizontal: sm);
  static const EdgeInsets paddingHorizontalMd =
      EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets paddingHorizontalLg =
      EdgeInsets.symmetric(horizontal: lg);

  // EdgeInsets - Verticales
  static const EdgeInsets paddingVerticalXs =
      EdgeInsets.symmetric(vertical: xs);
  static const EdgeInsets paddingVerticalSm =
      EdgeInsets.symmetric(vertical: sm);
  static const EdgeInsets paddingVerticalMd =
      EdgeInsets.symmetric(vertical: md);
  static const EdgeInsets paddingVerticalLg =
      EdgeInsets.symmetric(vertical: lg);

  // Layouts de contenedor
  static const EdgeInsets containerPadding = EdgeInsets.all(containerMargin);
  static const EdgeInsets screenPadding = EdgeInsets.symmetric(
    horizontal: containerMargin,
    vertical: md,
  );

  // Sombras
  static const BoxShadow shadowSm = BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.05),
    blurRadius: 4,
    offset: Offset(0, 2),
  );

  static const BoxShadow shadowMd = BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.1),
    blurRadius: 15,
    offset: Offset(0, 10),
  );

  static const List<BoxShadow> shadowSmList = [shadowSm];
  static const List<BoxShadow> shadowMdList = [shadowMd];
}
