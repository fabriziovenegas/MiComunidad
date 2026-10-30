import 'package:flutter/material.dart';

/// Keeps pasted/overlong text intact; form validation prevents sending it.
class LimitedTextFormField extends StatefulWidget {
  const LimitedTextFormField(
      {super.key,
      required this.characterLimit,
      this.controller,
      this.initialValue,
      this.onChanged,
      this.validator,
      this.decoration = const InputDecoration(),
      this.enabled = true,
      this.readOnly = false,
      this.minLines,
      this.maxLines = 1,
      this.keyboardType,
      this.textCapitalization = TextCapitalization.none});
  final int characterLimit;
  final TextEditingController? controller;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final InputDecoration decoration;
  final bool enabled, readOnly;
  final int? minLines, maxLines;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  @override
  State<LimitedTextFormField> createState() => _LimitedTextFormFieldState();
}

class _LimitedTextFormFieldState extends State<LimitedTextFormField> {
  TextEditingController? _owned;
  final _focus = FocusNode();
  TextEditingController get _controller => widget.controller ?? _owned!;
  void _listen() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _owned = TextEditingController(text: widget.initialValue);
    }
    _controller.addListener(_listen);
    _focus.addListener(_listen);
  }

  @override
  void didUpdateWidget(covariant LimitedTextFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      final previous = oldWidget.controller ?? _owned!;
      previous.removeListener(_listen);
      final value = previous.value;
      _owned?.dispose();
      _owned = widget.controller == null
          ? TextEditingController.fromValue(value)
          : null;
      _controller.addListener(_listen);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_listen);
    _owned?.dispose();
    _focus.removeListener(_listen);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Match the existing Dart/backend string-length validations, including
    // supplementary Unicode characters. Do not silently truncate pasted input.
    final count = _controller.text.length;
    final over = count > widget.characterLimit;
    final error = 'No puede superar los ${widget.characterLimit} caracteres.';
    return TextFormField(
      controller: _controller,
      focusNode: _focus,
      onChanged: widget.onChanged,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      keyboardType: widget.keyboardType,
      textCapitalization: widget.textCapitalization,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (value) => (value ?? '').length > widget.characterLimit
          ? error
          : widget.validator?.call(value),
      decoration: widget.decoration.copyWith(
        counterText:
            _focus.hasFocus || over ? '$count/${widget.characterLimit}' : '',
        counterStyle:
            over ? TextStyle(color: Theme.of(context).colorScheme.error) : null,
        errorText: over ? error : widget.decoration.errorText,
        errorMaxLines: 3,
      ),
    );
  }
}
