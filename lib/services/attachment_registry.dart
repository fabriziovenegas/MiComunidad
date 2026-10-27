import 'package:cloud_functions/cloud_functions.dart';

/// Metadata is registered only after the backend checks the real Storage object.
/// A retry keeps the same attachment ID; no client URL or uploader is submitted.
class AttachmentRegistry {
  static Future<void> register(Map<String, dynamic> fields) async {
    await FirebaseFunctions.instanceFor(region: 'southamerica-east1')
        .httpsCallable('registerContentAttachment')
        .call(fields);
  }

  static Future<void> delete(Map<String, dynamic> fields) async {
    await FirebaseFunctions.instanceFor(region: 'southamerica-east1')
        .httpsCallable('deleteContentAttachment')
        .call(fields);
  }
}
