import 'package:cloud_firestore/cloud_firestore.dart';

/// Edits an existing activity without replacing its record or related content.
class EventContentEditor {
  const EventContentEditor(
      {required this.firestore, required this.currentUserId});
  final FirebaseFirestore firestore;
  final String? Function() currentUserId;

  Future<void> save(String eventId, Map<String, dynamic> fields) async {
    final userId = currentUserId();
    if (userId == null || userId.isEmpty) {
      throw FirebaseException(
          plugin: 'cloud_firestore', code: 'unauthenticated');
    }
    const allowed = {'title', 'location', 'description', 'eventDate'};
    if (fields.keys.toSet().length != allowed.length ||
        !fields.keys.toSet().containsAll(allowed) ||
        fields['title'] is! String ||
        (fields['title'] as String).trim().isEmpty ||
        fields['location'] is! String ||
        fields['description'] is! String ||
        fields['eventDate'] is! Timestamp) {
      throw ArgumentError('Revisa los datos de la actividad.');
    }
    final payload = Map<String, dynamic>.from(fields);
    final reference = firestore.collection('events').doc(eventId);
    // Keep expected errors outside the native transaction callback, matching
    // the pending-content delivery contract and avoiding double completion.
    final failure =
        await firestore.runTransaction<Object?>((transaction) async {
      try {
        final profile =
            await transaction.get(firestore.collection('users').doc(userId));
        if (currentUserId() != userId ||
            profile.data()?['approvalStatus'] != 'aprobado' ||
            profile.data()?['role'] != 'admin') {
          return FirebaseException(
              plugin: 'cloud_firestore', code: 'permission-denied');
        }
        final event = await transaction.get(reference);
        if (!event.exists) {
          return FirebaseException(
              plugin: 'cloud_firestore', code: 'not-found');
        }
        if (currentUserId() != userId) {
          return FirebaseException(
              plugin: 'cloud_firestore', code: 'permission-denied');
        }
        if (payload.entries
            .every((entry) => event.data()![entry.key] == entry.value)) {
          return null;
        }
        transaction.update(
            reference, {...payload, 'updatedAt': FieldValue.serverTimestamp()});
        return null;
      } catch (error) {
        return error;
      }
    });
    if (failure != null) throw failure;
  }
}
