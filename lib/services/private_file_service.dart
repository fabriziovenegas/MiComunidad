import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';

/// Accept only this project's Storage objects, including old token URLs. Tokens
/// are ignored: every read uses the authenticated SDK and current Storage Rules.
class PrivateFileService {
  static const _channel = MethodChannel('micomunidad/private_files');

  static String objectPath(String value, String bucket) {
    final uri = Uri.tryParse(value);
    String? path;
    if (uri != null &&
        uri.scheme == 'gs' &&
        uri.host == bucket &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment) {
      path = uri.pathSegments.join('/');
    } else if (uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'firebasestorage.googleapis.com' &&
        uri.port == 443 &&
        uri.userInfo.isEmpty &&
        !uri.hasFragment) {
      final parts = uri.pathSegments;
      if (parts.length == 5 &&
          parts[0] == 'v0' &&
          parts[1] == 'b' &&
          parts[2] == bucket &&
          parts[3] == 'o') {
        path = parts[4];
      }
    }
    final parts = path?.split('/') ?? [];
    final valid = parts.length == 4 &&
        const ['projects', 'reports', 'events'].contains(parts[0]) &&
        (parts[2] == 'photos' ||
            (const ['events', 'projects'].contains(parts[0]) &&
                parts[2] == 'minutes'));
    final identity = parts.length == 4 &&
        parts[0] == 'access_requests' &&
        parts[2] == 'identity';
    if ((!valid && !identity) ||
        path == null ||
        path.length > 800 ||
        parts.any((part) =>
            part.isEmpty ||
            part == '.' ||
            part == '..' ||
            !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(part))) {
      throw const FormatException('El archivo no pertenece a este proyecto.');
    }
    return path;
  }

  static Future<Uint8List> read(String url) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Debes iniciar sesión.');
    final storage = FirebaseStorage.instance;
    final path = objectPath(url, storage.ref().bucket);
    final bytes = await storage.ref(path).getData(10 * 1024 * 1024);
    if (FirebaseAuth.instance.currentUser?.uid != user.uid || bytes == null) {
      throw StateError('La cuenta del archivo cambió.');
    }
    return bytes;
  }

  static Future<void> open(String url, {String? name}) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final storage = FirebaseStorage.instance;
    final path = objectPath(url, storage.ref().bucket);
    final metadata = await storage.ref(path).getMetadata();
    if (!const ['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
        .contains(metadata.contentType)) {
      throw const FormatException('Formato no compatible.');
    }
    final bytes = await read(url);
    if (userId == null || FirebaseAuth.instance.currentUser?.uid != userId) {
      throw StateError('La cuenta del archivo cambió.');
    }
    await _channel.invokeMethod<void>('openDocument', {
      'bytes': bytes,
      'contentType': metadata.contentType,
    });
  }
}
