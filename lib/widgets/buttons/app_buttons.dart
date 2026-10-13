import 'package:flutter/material.dart';
import '../../utils/constants.dart';

// ============================================================================
// PRIMARY BUTTON
// ============================================================================

class PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final bool isLoading;
  final bool isEnabled;
  final double? width;
  final double height;
  final EdgeInsets padding;
  final IconData? icon;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.isEnabled = true,
    this.width,
    this.height = 48,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    this.icon,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.isEnabled && !widget.isLoading
          ? (_) => setState(() => _isPressed = true)
          : null,
      onTapUp: widget.isEnabled && !widget.isLoading
          ? (_) {
              setState(() => _isPressed = false);
              widget.onPressed();
            }
          : null,
      onTapCancel: widget.isEnabled && !widget.isLoading
          ? () => setState(() => _isPressed = false)
          : null,
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
        duration: AppDurations.fast,
        child: Container(
          width: widget.width ?? double.infinity,
          height: widget.height,
          decoration: BoxDecoration(
            color: widget.isEnabled
                ? (widget.isLoading
                    ? AppColors.primary.withValues(alpha: 0.8)
                    : AppColors.primary)
                : AppColors.primary.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppBorderRadius.medium),
            boxShadow:
                !_isPressed && widget.isEnabled ? [AppShadows.small] : [],
          ),
          child: Center(
            child: widget.isLoading
                ? SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 2,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, color: Colors.white, size: 20),
                        SizedBox(width: AppSpacing.sm),
                      ],
                      Text(
                        widget.label,
                        style: AppTypography.buttonText,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SECONDARY BUTTON
// ============================================================================

class SecondaryButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final bool isEnabled;
  final double? width;
  final double height;
  final EdgeInsets padding;
  final IconData? icon;

  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isEnabled = true,
    this.width,
    this.height = 48,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    this.icon,
  });

  @override
  State<SecondaryButton> createState() => _SecondaryButtonState();
}

class _SecondaryButtonState extends State<SecondaryButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.isEnabled ? widget.onPressed : null,
        child: Container(
          width: widget.width ?? double.infinity,
          height: widget.height,
          decoration: BoxDecoration(
            color: _isHovered && widget.isEnabled
                ? AppColors.background
                : AppColors.surface,
            border: Border.all(
              color: widget.isEnabled
                  ? AppColors.primary
                  : AppColors.primary.withValues(alpha: 0.5),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(AppBorderRadius.medium),
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(
                    widget.icon,
                    color: widget.isEnabled
                        ? AppColors.primary
                        : AppColors.textDisabled,
                    size: 20,
                  ),
                  SizedBox(width: AppSpacing.sm),
                ],
                Text(
                  widget.label,
                  style: AppTypography.buttonSecondaryText.copyWith(
                    color: widget.isEnabled
                        ? AppColors.primary
                        : AppColors.textDisabled,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// TEXT BUTTON (Link)
// ============================================================================

class TextButtonWidget extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final bool isEnabled;
  final TextStyle? style;

  const TextButtonWidget({
    super.key,
    required this.label,
    required this.onPressed,
    this.isEnabled = true,
    this.style,
  });

  @override
  State<TextButtonWidget> createState() => _TextButtonWidgetState();
}

class _TextButtonWidgetState extends State<TextButtonWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.isEnabled ? widget.onPressed : null,
        child: Text(
          widget.label,
          style: (widget.style ?? AppTypography.bodySmall).copyWith(
            color: _isHovered && widget.isEnabled
                ? AppColors.primary.withValues(alpha: 0.8)
                : (widget.isEnabled
                    ? AppColors.primary
                    : AppColors.textDisabled),
            decoration: _isHovered && widget.isEnabled
                ? TextDecoration.underline
                : TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// DANGER BUTTON (Para eliminar/rechazar)
// ============================================================================

class DangerButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final bool isLoading;
  final bool isEnabled;
  final double? width;
  final double height;
  final IconData? icon;

  const DangerButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.isEnabled = true,
    this.width,
    this.height = 48,
    this.icon,
  });

  @override
  State<DangerButton> createState() => _DangerButtonState();
}

class _DangerButtonState extends State<DangerButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.isEnabled && !widget.isLoading
          ? (_) => setState(() => _isPressed = true)
          : null,
      onTapUp: widget.isEnabled && !widget.isLoading
          ? (_) {
              setState(() => _isPressed = false);
              widget.onPressed();
            }
          : null,
      onTapCancel: widget.isEnabled && !widget.isLoading
          ? () => setState(() => _isPressed = false)
          : null,
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
        duration: AppDurations.fast,
        child: Container(
          width: widget.width ?? double.infinity,
          height: widget.height,
          decoration: BoxDecoration(
            color: widget.isEnabled
                ? (widget.isLoading
                    ? AppColors.error.withValues(alpha: 0.8)
                    : AppColors.error)
                : AppColors.error.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppBorderRadius.medium),
            boxShadow:
                !_isPressed && widget.isEnabled ? [AppShadows.small] : [],
          ),
          child: Center(
            child: widget.isLoading
                ? SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 2,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, color: Colors.white, size: 20),
                        SizedBox(width: AppSpacing.sm),
                      ],
                      Text(
                        widget.label,
                        style: AppTypography.buttonText,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SUCCESS BUTTON
// ============================================================================

class SuccessButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final bool isLoading;
  final bool isEnabled;
  final double? width;
  final double height;
  final IconData? icon;

  const SuccessButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.isEnabled = true,
    this.width,
    this.height = 48,
    this.icon,
  });

  @override
  State<SuccessButton> createState() => _SuccessButtonState();
}

class _SuccessButtonState extends State<SuccessButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.isEnabled && !widget.isLoading
          ? (_) => setState(() => _isPressed = true)
          : null,
      onTapUp: widget.isEnabled && !widget.isLoading
          ? (_) {
              setState(() => _isPressed = false);
              widget.onPressed();
            }
          : null,
      onTapCancel: widget.isEnabled && !widget.isLoading
          ? () => setState(() => _isPressed = false)
          : null,
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
        duration: AppDurations.fast,
        child: Container(
          width: widget.width ?? double.infinity,
          height: widget.height,
          decoration: BoxDecoration(
            color: widget.isEnabled
                ? (widget.isLoading
                    ? AppColors.success.withValues(alpha: 0.8)
                    : AppColors.success)
                : AppColors.success.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppBorderRadius.medium),
            boxShadow:
                !_isPressed && widget.isEnabled ? [AppShadows.small] : [],
          ),
          child: Center(
            child: widget.isLoading
                ? SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 2,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, color: Colors.white, size: 20),
                        SizedBox(width: AppSpacing.sm),
                      ],
                      Text(
                        widget.label,
                        style: AppTypography.buttonText,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
