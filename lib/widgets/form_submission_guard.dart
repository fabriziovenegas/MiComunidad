import 'dart:async';
import 'package:flutter/material.dart';
import 'upload_error_notice.dart';

/// Keeps a form mounted and blocks repeated submission until confirmation.
class FormSubmissionGuard extends StatefulWidget {
  const FormSubmissionGuard({
    super.key,
    required this.onSubmit,
    required this.onSubmitted,
    required this.builder,
    this.validate,
    this.slowAfter,
    this.errorMessage,
  });

  final Future<void> Function() onSubmit;
  final void Function(BuildContext context) onSubmitted;
  final bool Function()? validate;
  final Duration? slowAfter;
  final String Function(Object error)? errorMessage;

  static bool isTakingLong(BuildContext context) =>
      context.findAncestorStateOfType<_FormSubmissionGuardState>()?._slow ??
      false;
  final Widget Function(BuildContext context, bool saving, VoidCallback submit)
      builder;

  @override
  State<FormSubmissionGuard> createState() => _FormSubmissionGuardState();
}

class _FormSubmissionGuardState extends State<FormSubmissionGuard> {
  bool _saving = false;
  bool _submitted = false;
  bool _slow = false;
  Timer? _slowTimer;

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving || _submitted || widget.validate?.call() == false) return;
    FocusManager.instance.primaryFocus?.unfocus();
    dismissUploadError();
    setState(() {
      _saving = true;
      _slow = false;
    });
    if (widget.slowAfter case final Duration delay) {
      _slowTimer = Timer(delay, () {
        if (!mounted || !_saving) return;
        setState(() => _slow = true);
        showWarningNotice(
            context, 'El guardado está tardando. Comprueba tu conexión');
      });
    }
    try {
      await widget.onSubmit();
      if (!mounted) return;
      setState(() {
        _submitted = true;
        _saving = false;
      });
      dismissUploadError();
      widget.onSubmitted(context);
    } catch (error) {
      if (mounted) {
        // Reuse the root red notice so it stays above the open form.
        showUploadError(
            context,
            widget.errorMessage?.call(error) ??
                'Hubo un problema con el envío. Tus datos se conservan.');
      }
    } finally {
      _slowTimer?.cancel();
      if (mounted && !_submitted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving || _slow,
        child: Builder(
            builder: (context) =>
                widget.builder(context, _saving || _submitted, _submit)),
      );
}
