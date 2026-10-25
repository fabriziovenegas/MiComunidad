import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// One form instance owns one document ID. Retries never allocate another ID.
class ContentCreationDraft {
  ContentCreationDraft({
    required String collection,
    FirebaseFirestore? firestore,
    String? Function()? currentUserId,
    String? expectedUserId,
  })  : assert(const ['projects', 'reports', 'events'].contains(collection)),
        _collection = collection,
        _reference = (firestore ?? FirebaseFirestore.instance)
            .collection(collection)
            .doc(),
        _currentUserId = currentUserId ?? _signedInUserId,
        _ownerId = expectedUserId;

  final String _collection;
  final DocumentReference<Map<String, dynamic>> _reference;
  final String? Function() _currentUserId;
  String? _ownerId;
  bool _attempted = false;
  Future<void>? _inFlight;

  String get id => _reference.id;

  static String? _signedInUserId() {
    final user = FirebaseAuth.instance.currentUser;
    return user == null || user.isAnonymous ? null : user.uid;
  }

  Future<void> save(Map<String, dynamic> fields) {
    if (_inFlight != null) return _inFlight!;
    return _inFlight = _save(Map<String, dynamic>.from(fields))
        .whenComplete(() => _inFlight = null);
  }

  Future<bool> _alreadySaved(Map<String, dynamic> fields) async {
    final snapshot =
        await _reference.get(const GetOptions(source: Source.server));
    if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) {
      throw StateError('El servidor todavía no confirmó este registro.');
    }
    if (!snapshot.exists) return false;
    final saved = snapshot.data()!;
    // Never overwrite another record or silently accept different content.
    if (saved['createdBy'] != _ownerId ||
        fields.entries.any((entry) =>
            entry.key != 'createdByName' && saved[entry.key] != entry.value)) {
      throw StateError('El registro existente no coincide con este borrador.');
    }
    return true;
  }

  Future<void> _save(Map<String, dynamic> fields) async {
    final uid = _currentUserId();
    if (uid == null || (_ownerId != null && uid != _ownerId)) {
      throw StateError('La cuenta del envío ya no está disponible.');
    }
    _ownerId ??= uid;
    if (_attempted) {
      try {
        if (await _alreadySaved(fields)) return;
      } on FirebaseException catch (error) {
        // Existing rules intentionally hide nonexistent reports from residents.
        // A write still has to pass the original creation rules; do not broaden
        // profile/report reads just to check whether a new report exists.
        if (_collection != 'reports' || error.code != 'permission-denied') {
          rethrow;
        }
      }
    }
    _attempted = true;
    try {
      await _reference.set({
        ...fields,
        if (_collection == 'projects') 'isTrashed': false,
        if (_collection == 'reports') ...{
          'status': 'pendiente',
          'moderationStatus': 'pendiente',
        },
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // A lost acknowledgement is not evidence that the write failed. Only a
      // fresh server read of this exact draft can turn that error into success.
      try {
        if (await _alreadySaved(fields)) return;
      } catch (_) {
        // Keep the original write error and the open form when uncertain.
      }
      rethrow;
    }
  }
}
