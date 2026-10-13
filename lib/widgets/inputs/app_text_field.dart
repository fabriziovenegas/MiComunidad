import 'package:flutter/material.dart';
import '../../utils/constants.dart';

// ============================================================================
// APP TEXT FIELD
// ============================================================================

class AppTextField extends StatefulWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final TextInputType keyboardType;
  final bool obscureText;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function()? onEditingComplete;
  final int maxLines;
  final int? maxLength;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixIconPressed;
  final bool isRequired;
  final bool enabled;
  final TextInputAction textInputAction;

  const AppTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.validator,
    this.onChanged,
    this.onEditingComplete,
    this.maxLines = 1,
    this.maxLength,
    this.prefixIcon,
    this.suffixIcon,
    this.onSuffixIconPressed,
    this.isRequired = false,
    this.enabled = true,
    this.textInputAction = TextInputAction.next,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _obscureText;
  String? _errorText;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.obscureText;
  }

  void _validateField() {
    if (widget.validator != null) {
      final error = widget.validator!(widget.controller?.text);
      setState(() => _errorText = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Row(
          children: [
            Text(
              widget.label,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (widget.isRequired)
              Text(
                ' *',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        SizedBox(height: AppSpacing.sm),

        // Input Field
        Focus(
          onFocusChange: (hasFocus) {
            setState(() => _isFocused = hasFocus);
            if (!hasFocus) _validateField();
          },
          child: TextField(
            controller: widget.controller,
            keyboardType: widget.keyboardType,
            obscureText: _obscureText && widget.obscureText,
            maxLines: _obscureText && widget.obscureText ? 1 : widget.maxLines,
            maxLength: widget.maxLength,
            enabled: widget.enabled,
            textInputAction: widget.textInputAction,
            onChanged: (value) {
              widget.onChanged?.call(value);
              _validateField();
            },
            onEditingComplete: widget.onEditingComplete,
            style: AppTypography.bodyMedium,
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: AppTypography.bodySmall.copyWith(
                color: AppColors.textLight,
              ),
              prefixIcon: widget.prefixIcon != null
                  ? Icon(
                      widget.prefixIcon,
                      color:
                          _isFocused ? AppColors.primary : AppColors.textLight,
                      size: 20,
                    )
                  : null,
              suffixIcon: widget.suffixIcon != null
                  ? GestureDetector(
                      onTap: widget.onSuffixIconPressed,
                      child: Icon(
                        widget.suffixIcon,
                        color: AppColors.textLight,
                        size: 20,
                      ),
                    )
                  : (_errorText != null && _isFocused)
                      ? Icon(
                          Icons.error_outline,
                          color: AppColors.error,
                          size: 20,
                        )
                      : null,
              filled: true,
              fillColor:
                  widget.enabled ? AppColors.surface : AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppBorderRadius.medium),
                borderSide: BorderSide(
                  color: AppColors.borderLight,
                  width: 1,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppBorderRadius.medium),
                borderSide: BorderSide(
                  color: _errorText != null
                      ? AppColors.error
                      : AppColors.borderLight,
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppBorderRadius.medium),
                borderSide: BorderSide(
                  color:
                      _errorText != null ? AppColors.error : AppColors.primary,
                  width: 2,
                ),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
              counterText: '',
            ),
          ),
        ),

        // Error Message
        if (_errorText != null)
          Padding(
            padding: EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              children: [
                Icon(
                  Icons.warning_rounded,
                  color: AppColors.error,
                  size: 14,
                ),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _errorText!,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),

        SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

// ============================================================================
// APP PASSWORD FIELD
// ============================================================================

class AppPasswordField extends StatefulWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final bool isRequired;

  const AppPasswordField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.validator,
    this.onChanged,
    this.isRequired = false,
  });

  @override
  State<AppPasswordField> createState() => _AppPasswordFieldState();
}

class _AppPasswordFieldState extends State<AppPasswordField> {
  bool _showPassword = false;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: widget.label,
      hint: widget.hint ?? 'Ingresa tu contraseña',
      controller: widget.controller,
      keyboardType: TextInputType.visiblePassword,
      obscureText: !_showPassword,
      validator: widget.validator,
      onChanged: widget.onChanged,
      isRequired: widget.isRequired,
      prefixIcon: Icons.lock_outline,
      suffixIcon: _showPassword ? Icons.visibility : Icons.visibility_off,
      onSuffixIconPressed: () {
        setState(() => _showPassword = !_showPassword);
      },
    );
  }
}

// ============================================================================
// APP TEXTAREA
// ============================================================================

class AppTextArea extends StatefulWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final int maxLines;
  final int? maxLength;
  final int minLines;
  final bool isRequired;

  const AppTextArea({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.validator,
    this.onChanged,
    this.maxLines = 5,
    this.maxLength = 500,
    this.minLines = 3,
    this.isRequired = false,
  });

  @override
  State<AppTextArea> createState() => _AppTextAreaState();
}

class _AppTextAreaState extends State<AppTextArea> {
  String? _errorText;

  void _validateField() {
    if (widget.validator != null) {
      final error = widget.validator!(widget.controller?.text);
      setState(() => _errorText = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Row(
          children: [
            Text(
              widget.label,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (widget.isRequired)
              Text(
                ' *',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        SizedBox(height: AppSpacing.sm),

        // TextArea
        Focus(
          onFocusChange: (hasFocus) {
            if (!hasFocus) _validateField();
          },
          child: TextField(
            controller: widget.controller,
            maxLines: widget.maxLines,
            minLines: widget.minLines,
            maxLength: widget.maxLength,
            onChanged: (value) {
              widget.onChanged?.call(value);
              _validateField();
            },
            style: AppTypography.bodyMedium,
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: AppTypography.bodySmall.copyWith(
                color: AppColors.textLight,
              ),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppBorderRadius.medium),
                borderSide: BorderSide(
                  color: AppColors.borderLight,
                  width: 1,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppBorderRadius.medium),
                borderSide: BorderSide(
                  color: _errorText != null
                      ? AppColors.error
                      : AppColors.borderLight,
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppBorderRadius.medium),
                borderSide: BorderSide(
                  color:
                      _errorText != null ? AppColors.error : AppColors.primary,
                  width: 2,
                ),
              ),
              contentPadding: EdgeInsets.all(AppSpacing.md),
              counterText: '',
            ),
          ),
        ),

        // Error Message
        if (_errorText != null)
          Padding(
            padding: EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              children: [
                Icon(
                  Icons.warning_rounded,
                  color: AppColors.error,
                  size: 14,
                ),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _errorText!,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),

        SizedBox(height: AppSpacing.md),
      ],
    );
  }
}
