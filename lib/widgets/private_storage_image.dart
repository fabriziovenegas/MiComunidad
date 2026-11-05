import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/private_file_service.dart';
import '../services/upload_connection.dart';

/// Same image presentation; private bytes never use an unauthenticated URL.
class PrivateStorageImage extends StatefulWidget {
  const PrivateStorageImage(this.url,
      {super.key,
      this.width,
      this.height,
      this.fit,
      this.errorBuilder,
      this.loadingBuilder,
      this.read,
      this.isOffline});
  final Future<Uint8List> Function(String)? read;
  final Future<bool> Function()? isOffline;
  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;

  @override
  State<PrivateStorageImage> createState() => _PrivateStorageImageState();
}

class _PrivateStorageImageState extends State<PrivateStorageImage> {
  late Future<Uint8List> _bytes;
  Future<Uint8List> _load() => (() async {
        if (await (widget.isOffline ?? UploadConnection.isOffline)()) {
          throw StateError('offline');
        }
        return (widget.read ?? PrivateFileService.read)(widget.url);
      })()
          .timeout(const Duration(seconds: 30));

  Widget _error(BuildContext context, Object error, StackTrace? stack) =>
      SizedBox(
          width: widget.width,
          height: widget.height,
          child: LayoutBuilder(builder: (context, constraints) {
            const message =
                'No se pudo cargar la fotografía. Verifica tu conexión';
          void retry() => setState(() {
                _bytes = _load();
              });
            if (constraints.maxWidth < 180 || constraints.maxHeight < 150) {
              return Center(
                  child: IconButton(
                      tooltip: '$message. Reintentar',
                      onPressed: retry,
                      icon: const Icon(Icons.refresh)));
            }
            return Center(
                child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          if (widget.errorBuilder != null)
                            widget.errorBuilder!(context, error, stack)
                          else
                            const Icon(Icons.broken_image_outlined),
                          const SizedBox(height: 8),
                          const Text(message, textAlign: TextAlign.center),
                          TextButton(
                              onPressed: retry,
                              child: const Text('Reintentar')),
                        ]))));
          }));
  @override
  void initState() {
    super.initState();
    _bytes = _load();
  }

  @override
  void didUpdateWidget(covariant PrivateStorageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _bytes = _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _error(context, snapshot.error!, snapshot.stackTrace);
          }
          if (!snapshot.hasData) {
            return SizedBox(
                width: widget.width,
                height: widget.height,
                child: const Center(child: CircularProgressIndicator()));
          }
          return Image.memory(snapshot.data!,
              width: widget.width,
              height: widget.height,
              fit: widget.fit,
              errorBuilder: _error);
        },
      );
}
