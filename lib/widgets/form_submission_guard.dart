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
  });

  final Future<void> Function() onSubmit;
  final void Function(BuildContext context) onSubmitted;
  final bool Function()? validate;
  final Widget Function(BuildContext context, bool saving, VoidCallback submit)
      builder;

  @override
  State<FormSubmissionGuard> createState() => _FormSubmissionGuardState();
}

class _FormSubmissionGuardState extends State<FormSubmissionGuard> {
  bool _saving = false;
  bool _submitted = false;

  Future<void> _submit() async {
    if (_saving || _submitted || widget.validate?.call() == false) return;
    FocusManager.instance.primaryFocus?.unfocus();
    dismissUploadError();
    setState(() => _saving = true);
    try {
      await widget.onSubmit();
      if (!mounted) return;
      setState(() {
        _submitted = true;
        _saving = false;
      });
      widget.onSubmitted(context);
    } catch (_) {
      if (mounted) {
        // Reuse the root red notice so it stays above the open form.
        showUploadError(
            context, 'Hubo un problema con el envío. Tus datos se conservan.');
      }
    } finally {
      if (mounted && !_submitted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: widget.builder(context, _saving || _submitted, _submit),
      );
}
