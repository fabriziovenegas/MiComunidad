import 'dart:async';
import 'package:flutter/material.dart';

VoidCallback? _dismissUploadError;

void dismissUploadError() => _dismissUploadError?.call();

/// Uses the root overlay so dialogs and expanded bottom sheets cannot hide it.
void showUploadError(BuildContext context, String message) =>
    _showNotice(context, message, isError: true);

/// Shows a confirmed save above the closing form and the navigation bar.
void showSuccessNotice(BuildContext context, String message) =>
    _showNotice(context, message, isError: false);

void showWarningNotice(BuildContext context, String message) =>
    _showNotice(context, message, isError: false, isWarning: true);

void _showNotice(BuildContext context, String message,
    {required bool isError, bool isWarning = false}) {
  if (!context.mounted) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _dismissUploadError?.call();

  late final OverlayEntry entry;
  var dismissed = false;
  void dismiss() {
    if (dismissed) return;
    dismissed = true;
    if (_dismissUploadError == dismiss) _dismissUploadError = null;
    entry.remove();
    entry.dispose();
  }

  entry = OverlayEntry(
    builder: (_) => _OverlayNotice(
      message: message,
      isError: isError,
      isWarning: isWarning,
      onDismiss: dismiss,
      onDisposed: () {
        dismissed = true;
        if (_dismissUploadError == dismiss) _dismissUploadError = null;
      },
    ),
  );
  _dismissUploadError = dismiss;
  overlay.insert(entry);
}

class _OverlayNotice extends StatefulWidget {
  const _OverlayNotice({
    required this.message,
    required this.isError,
    required this.isWarning,
    required this.onDismiss,
    required this.onDisposed,
  });

  final String message;
  final bool isError, isWarning;
  final VoidCallback onDismiss;
  final VoidCallback onDisposed;

  @override
  State<_OverlayNotice> createState() => _OverlayNoticeState();
}

class _OverlayNoticeState extends State<_OverlayNotice> {
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Screen-reader users can dismiss the notice when they have read it.
    if (!MediaQuery.accessibleNavigationOf(context)) {
      _timer = Timer(const Duration(seconds: 5), widget.onDismiss);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.onDisposed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          bottom: false,
          minimum: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Semantics(
                liveRegion: true,
                container: true,
                child: Material(
                  key: ValueKey(widget.isWarning
                      ? 'save-warning-notice'
                      : widget.isError
                          ? 'upload-error-notice'
                          : 'save-success-notice'),
                  color: widget.isWarning
                      ? const Color(0xFFFFE6A7)
                      : widget.isError
                          ? const Color(0xFFB3261E)
                          : const Color(0xFF276749),
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                    child: Row(
                      children: [
                        Icon(
                            widget.isWarning
                                ? Icons.schedule_outlined
                                : widget.isError
                                    ? Icons.error_outline
                                    : Icons.check_circle_outline,
                            color: widget.isWarning
                                ? const Color(0xFF5D4300)
                                : Colors.white),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(widget.message,
                              style: TextStyle(
                                  color: widget.isWarning
                                      ? const Color(0xFF5D4300)
                                      : Colors.white)),
                        ),
                        IconButton(
                          tooltip: 'Cerrar aviso',
                          onPressed: widget.onDismiss,
                          icon: Icon(Icons.close,
                              color: widget.isWarning
                                  ? const Color(0xFF5D4300)
                                  : Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
