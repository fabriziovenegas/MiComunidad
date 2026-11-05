import 'package:cloud_firestore/cloud_firestore.dart';

/// Transactions require the server and never persist an offline write queue.
class OnlineAdminActionWriter {
  const OnlineAdminActionWriter(
      {required this.firestore, required this.currentUserId});
  final FirebaseFirestore firestore;
  final String? Function() currentUserId;

  Future<void> archiveProject(String id) => _write('projects', id, {
        'isTrashed': true,
        'trashedAt': FieldValue.serverTimestamp(),
      });

  Future<void> deleteMapPoint(String id) =>
      _write('mapPoints', id, {}, delete: true);

  Future<void> restoreProject(String id) => _write('projects', id, {
        'isTrashed': false,
        'trashedAt': FieldValue.delete(),
      });

  Future<void> changeReportStatus(String id, String status) {
    if (!const ['pendiente', 'en_proceso', 'resuelto'].contains(status)) {
      throw ArgumentError.value(status, 'status');
    }
    return _write('reports', id, {'status': status});
  }

  Future<void> _write(String collection, String id, Map<String, dynamic> fields,
      {bool delete = false}) async {
    final uid = currentUserId();
    if (uid == null || uid.isEmpty) {
      throw FirebaseException(
          plugin: 'cloud_firestore', code: 'unauthenticated');
    }
    final reference = firestore.collection(collection).doc(id);
    // Return expected failures; throw outside the native callback, as in the
    // existing content editors, to avoid double completion on Android.
    final failure =
        await firestore.runTransaction<Object?>((transaction) async {
      try {
        final profile =
            await transaction.get(firestore.collection('users').doc(uid));
        final data = profile.data();
        if (currentUserId() != uid ||
            data?['role'] != 'admin' ||
            data?['approvalStatus'] != 'aprobado' ||
            data?['withdrawnAt'] != null) {
          return FirebaseException(
              plugin: 'cloud_firestore', code: 'permission-denied');
        }
        final record = await transaction.get(reference);
        if (!record.exists && delete) return null;
        if (!record.exists) {
          return FirebaseException(
              plugin: 'cloud_firestore', code: 'not-found');
        }
        final saved = record.data()!;
        if (currentUserId() != uid ||
            saved['deletionInProgress'] == true ||
            (collection == 'reports' &&
                saved['moderationStatus'] != 'aprobado')) {
          return FirebaseException(
              plugin: 'cloud_firestore', code: 'permission-denied');
        }
        if (delete) {
          transaction.delete(reference);
        } else {
          transaction.update(reference,
              {...fields, 'updatedAt': FieldValue.serverTimestamp()});
        }
        return null;
      } catch (error) {
        return error;
      }
    });
    if (failure != null) throw failure;
  }
}
