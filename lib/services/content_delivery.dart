import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/report_edit.dart';
import 'pending_content.dart';

abstract class ContentDelivery {
  Future<void> deliver(PendingContent item);
}

class FirebaseContentDelivery implements ContentDelivery {
  FirebaseContentDelivery(
      {FirebaseFirestore? firestore, String? Function()? currentUserId})
      : _firestore = firestore,
        _currentUserId =
            currentUserId ?? (() => FirebaseAuth.instance.currentUser?.uid);
  final FirebaseFirestore? _firestore;
  final String? Function() _currentUserId;

  @override
  Future<void> deliver(PendingContent item) async {
    item.validate();
    final db = _firestore ?? FirebaseFirestore.instance;
    final ref = db.doc(item.path);
    void account() {
      if (_currentUserId() != item.userId) {
        throw StateError('La cuenta del envío cambió.');
      }
    }

    account();
    final failure = await db.runTransaction<Object?>((transaction) async {
      // Return application/read failures as a no-write outcome. Throwing inside
      // this SDK's native transaction callback can complete its Future twice.
      // The original failure is rethrown below, outside the callback.
      try {
        account();
        final profile =
            await transaction.get(db.collection('users').doc(item.userId));
        final user = profile.data();
        if (user?['approvalStatus'] != 'aprobado' ||
            !const ['admin', 'vecino'].contains(user?['role']) ||
            (!item.isComment && user?['role'] != 'admin')) {
          throw FirebaseException(
              plugin: 'cloud_firestore', code: 'permission-denied');
        }
        // Read parent and existing comment before writing. A concurrent deletion
        // or archival invalidates the transaction rather than leaving an orphan.
        if (item.isComment) {
          final parent = await transaction
              .get(db.collection(item.collection).doc(item.parentId));
          final data = parent.data();
          if (!parent.exists) {
            throw FirebaseException(
                plugin: 'cloud_firestore', code: 'not-found');
          }
          if (data?['deletionInProgress'] == true ||
              (item.collection == 'reports' && !reportAcceptsComments(data!)) ||
              (item.collection == 'projects' && data?['isTrashed'] != false)) {
            throw FirebaseException(
                plugin: 'cloud_firestore', code: 'permission-denied');
          }
        }
        final existing = await transaction.get(ref);
        account();
        if (existing.exists) {
          final saved = existing.data()!;
          if (saved[item.isComment ? 'authorId' : 'createdBy'] != item.userId ||
              (item.isComment && saved['text'] != item.fields['text'])) {
            throw StateError(
                'El registro existente no coincide con este envío.');
          }
          // Never restore old content, progress, status or an archived project.
          return null;
        }
        transaction.set(ref, {
          ...item.fields,
          if (item.isComment)
            'authorId': item.userId
          else ...{
            'createdBy': item.userId,
            'updatedAt': FieldValue.serverTimestamp()
          },
          if (!item.isComment && item.collection == 'projects')
            'isTrashed': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return null;
      } catch (error) {
        return error;
      }
    });
    if (failure != null) throw failure;
  }
}
