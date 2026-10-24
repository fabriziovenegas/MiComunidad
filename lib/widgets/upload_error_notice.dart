import 'dart:async';
import 'package:flutter/material.dart';

VoidCallback? _dismissUploadError;

void dismissUploadError() => _dismissUploadError?.call();

/// Uses the root overlay so dialogs and expanded bottom sheets cannot hide it.
void showUploadError(BuildContext context, String message) {
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
    builder: (_) => _UploadErrorNotice(
      message: message,
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

class _UploadErrorNotice extends StatefulWidget {
  const _UploadErrorNotice({
    required this.message,
    required this.onDismiss,
    required this.onDisposed,
  });

  final String message;
  final VoidCallback onDismiss;
  final VoidCallback onDisposed;

  @override
  State<_UploadErrorNotice> createState() => _UploadErrorNoticeState();
}

class _UploadErrorNoticeState extends State<_UploadErrorNotice> {
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
                  key: const ValueKey('upload-error-notice'),
                  color: const Color(0xFFB3261E),
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.white),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(widget.message,
                              style: const TextStyle(color: Colors.white)),
                        ),
                        IconButton(
                          tooltip: 'Cerrar aviso',
                          onPressed: widget.onDismiss,
                          icon: const Icon(Icons.close, color: Colors.white),
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
