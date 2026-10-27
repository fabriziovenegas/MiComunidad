import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/private_file_service.dart';

/// Same image presentation; private bytes never use an unauthenticated URL.
class PrivateStorageImage extends StatefulWidget {
  const PrivateStorageImage(this.url,
      {super.key,
      this.width,
      this.height,
      this.fit,
      this.errorBuilder,
      this.loadingBuilder});
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
  @override
  void initState() {
    super.initState();
    _bytes = PrivateFileService.read(widget.url);
  }

  @override
  void didUpdateWidget(covariant PrivateStorageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _bytes = PrivateFileService.read(widget.url);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return widget.errorBuilder
                    ?.call(context, snapshot.error!, snapshot.stackTrace) ??
                SizedBox(
                    width: widget.width,
                    height: widget.height,
                    child: const Icon(Icons.broken_image_outlined));
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
              errorBuilder: widget.errorBuilder);
        },
      );
}
