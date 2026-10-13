import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import '../buttons/app_buttons.dart';

// ============================================================================
// APP CARD
// ============================================================================

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final double borderRadius;
  final VoidCallback? onTap;
  final BoxShadow? shadow;
  final Color? backgroundColor;
  final Border? border;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.margin = const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    this.borderRadius = AppBorderRadius.large,
    this.onTap,
    this.shadow,
    this.backgroundColor,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    Widget card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border ?? Border.all(color: AppColors.borderLight, width: 1),
        boxShadow: shadow != null ? [shadow!] : [AppShadows.small],
      ),
      child: child,
    );

    if (onTap != null) {
      card = GestureDetector(
        onTap: onTap,
        child: card,
      );
    }

    return Container(
      margin: margin,
      child: card,
    );
  }
}

// ============================================================================
// APP BADGE
// ============================================================================

class AppBadge extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final EdgeInsets padding;
  final double borderRadius;
  final TextStyle? textStyle;
  final IconData? icon;

  const AppBadge({
    super.key,
    required this.label,
    this.backgroundColor = AppColors.primary,
    this.textColor = Colors.white,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    this.borderRadius = 4,
    this.textStyle,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: textColor, size: 12),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: textStyle ??
                AppTypography.caption.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// STATUS BADGE
// ============================================================================

class StatusBadge extends StatelessWidget {
  final String status;

  const StatusBadge({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _getStatusColors(status);
    return AppBadge(
      label: status,
      backgroundColor: colors['bg']!,
      textColor: colors['text']!,
    );
  }

  Map<String, Color> _getStatusColors(String status) {
    switch (status) {
      case 'Pendiente':
        return {'bg': AppColors.warning, 'text': Colors.white};
      case 'En proceso':
        return {'bg': AppColors.info, 'text': Colors.white};
      case 'Finalizado':
      case 'Aprobada':
        return {'bg': AppColors.success, 'text': Colors.white};
      case 'Rechazada':
        return {'bg': AppColors.error, 'text': Colors.white};
      default:
        return {'bg': AppColors.textLight, 'text': Colors.white};
    }
  }
}

// ============================================================================
// PRIORITY BADGE
// ============================================================================

class PriorityBadge extends StatelessWidget {
  final String priority;

  const PriorityBadge({
    super.key,
    required this.priority,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _getPriorityColors(priority);
    return AppBadge(
      label: '${_getPriorityIcon(priority)} $priority',
      backgroundColor: colors['bg']!,
      textColor: colors['text']!,
    );
  }

  Map<String, Color> _getPriorityColors(String priority) {
    switch (priority) {
      case 'Alta':
        return {'bg': AppColors.error, 'text': Colors.white};
      case 'Media':
        return {'bg': AppColors.warning, 'text': Colors.white};
      case 'Baja':
        return {'bg': AppColors.success, 'text': Colors.white};
      default:
        return {'bg': AppColors.textLight, 'text': Colors.white};
    }
  }

  String _getPriorityIcon(String priority) {
    switch (priority) {
      case 'Alta':
        return '🔴';
      case 'Media':
        return '🟠';
      case 'Baja':
        return '🟡';
      default:
        return '•';
    }
  }
}

// ============================================================================
// APP PROGRESS BAR
// ============================================================================

class AppProgressBar extends StatelessWidget {
  final double progress; // 0-100
  final double height;
  final Color backgroundColor;
  final Color progressColor;
  final bool showLabel;
  final TextStyle? labelStyle;
  final Duration animationDuration;

  const AppProgressBar({
    super.key,
    required this.progress,
    this.height = 6,
    this.backgroundColor = AppColors.background,
    this.progressColor = AppColors.primary,
    this.showLabel = false,
    this.labelStyle,
    this.animationDuration = const Duration(milliseconds: 500),
  }) : assert(progress >= 0 && progress <= 100);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: Container(
            height: height,
            width: double.infinity,
            color: backgroundColor,
            child: AnimatedFractionallySizedBox(
              widthFactor: progress / 100,
              alignment: Alignment.centerLeft,
              duration: animationDuration,
              child: Container(
                color: progressColor,
              ),
            ),
          ),
        ),
        if (showLabel)
          Padding(
            padding: EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              '${progress.toStringAsFixed(0)}%',
              style: labelStyle ??
                  AppTypography.bodySmall.copyWith(
                    color: progressColor,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
      ],
    );
  }
}

// ============================================================================
// APP HEADER
// ============================================================================

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;

  const AppHeader({
    super.key,
    required this.title,
    this.showBackButton = false,
    this.onBackPressed,
    this.actions,
    this.bottom,
  });

  @override
  Size get preferredSize => Size.fromHeight(
        (AppSpacing.lg * 2) + 16 + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.secondary,
      elevation: 0,
      centerTitle: false,
      leading: showBackButton
          ? IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: onBackPressed ?? () => Navigator.pop(context),
            )
          : null,
      title: Text(
        title,
        style: AppTypography.headlineMedium.copyWith(
          color: Colors.white,
        ),
      ),
      actions: actions,
      bottom: bottom,
    );
  }
}

// ============================================================================
// EMPTY STATE
// ============================================================================

class EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onActionPressed;
  final String? actionLabel;
  final double iconSize;

  const EmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.inbox_outlined,
    this.onActionPressed,
    this.actionLabel,
    this.iconSize = 64,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: iconSize,
              color: AppColors.textLight,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              style: AppTypography.headlineMedium.copyWith(
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              subtitle,
              style: AppTypography.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onActionPressed != null) ...[
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: actionLabel!,
                onPressed: onActionPressed!,
                width: 200,
              ),
            ]
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// LOADING STATE
// ============================================================================

class LoadingState extends StatelessWidget {
  final String message;

  const LoadingState({
    super.key,
    this.message = 'Cargando...',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            strokeWidth: 3,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            message,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// USER AVATAR
// ============================================================================

class UserAvatar extends StatelessWidget {
  final String initials;
  final double size;
  final Color backgroundColor;
  final Color textColor;

  const UserAvatar({
    super.key,
    required this.initials,
    this.size = 44,
    this.backgroundColor = AppColors.primary,
    this.textColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: Center(
        child: Text(
          initials.length >= 2 ? initials.substring(0, 2) : initials,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: size / 2.5,
            fontFamily: 'Inter',
          ),
        ),
      ),
    );
  }
}
