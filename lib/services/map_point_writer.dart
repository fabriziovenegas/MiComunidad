import 'package:cloud_firestore/cloud_firestore.dart';

/// A fixed ID makes a retry safe after an acknowledgement was lost.
class MapPointWriter {
  const MapPointWriter({required this.firestore, required this.currentUserId});
  final FirebaseFirestore firestore;
  final String? Function() currentUserId;

  Future<void> save(
      {required String id,
      required String userId,
      required String title,
      required String description,
      required double latitude,
      required double longitude}) async {
    final fields = <String, dynamic>{
      'title': title.trim(),
      'description': description.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'createdBy': userId,
    };
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id) ||
        title.trim().isEmpty ||
        title.length > 160 ||
        description.length > 4000 ||
        !latitude.isFinite ||
        latitude.abs() > 90 ||
        !longitude.isFinite ||
        longitude.abs() > 180) {
      throw ArgumentError('Revisa los datos del punto.');
    }
    final ref = firestore.collection('mapPoints').doc(id);
    // Transactions require a server connection; do not queue a new point offline.
    final failure = await firestore.runTransaction<Object?>((tx) async {
      try {
        if (currentUserId() != userId || userId.isEmpty) {
          throw FirebaseException(
              plugin: 'cloud_firestore', code: 'unauthenticated');
        }
        final profile = await tx.get(firestore.collection('users').doc(userId));
        if (profile.data()?['role'] != 'admin' ||
            profile.data()?['approvalStatus'] != 'aprobado') {
          throw FirebaseException(
              plugin: 'cloud_firestore', code: 'permission-denied');
        }
        final existing = await tx.get(ref);
        if (currentUserId() != userId) {
          throw FirebaseException(
              plugin: 'cloud_firestore', code: 'unauthenticated');
        }
        if (existing.exists) {
          if (!fields.entries
              .every((e) => existing.data()?[e.key] == e.value)) {
            throw StateError('El punto existente no coincide con este envío.');
          }
          return null;
        }
        tx.set(ref, {...fields, 'createdAt': FieldValue.serverTimestamp()});
        return null;
      } catch (error) {
        return error;
      }
    });
    if (failure != null) throw failure;
  }
}
