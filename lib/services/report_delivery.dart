import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'pending_report_service.dart';
import 'file_service.dart';
import 'attachment_registry.dart';

abstract class ReportDelivery {
  Future<void> ensureReport(PendingReport item);
  Future<void> ensurePhoto(PendingReport item, File photo);
}

/// Stable document/object names allow recovery after a lost acknowledgement.
/// No updates to existing files or permission changes are needed.
class FirebaseReportDelivery implements ReportDelivery {
  FirebaseReportDelivery(
      {FirebaseFirestore? firestore,
      FirebaseStorage? storage,
      String? Function()? currentUserId,
      Future<void> Function()? refreshAuth,
      Future<void> Function(Map<String, dynamic>)? registerAttachment})
      : _firestore = firestore,
        _storage = storage,
        _currentUserId =
            currentUserId ?? (() => FirebaseAuth.instance.currentUser?.uid),
        _refreshAuth = refreshAuth ?? _refreshToken,
        _registerAttachment = registerAttachment ?? AttachmentRegistry.register;

  final FirebaseFirestore? _firestore;
  final FirebaseStorage? _storage;
  final String? Function() _currentUserId;
  final Future<void> Function() _refreshAuth;
  final Future<void> Function(Map<String, dynamic>) _registerAttachment;
  static Future<void> _refreshToken() async {
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
  }

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;
  FirebaseStorage get _files => _storage ?? FirebaseStorage.instance;

  void _checkAccount(PendingReport item) {
    if (_currentUserId() != item.userId) {
      throw StateError('La cuenta del envío cambió.');
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _fresh(
      DocumentReference<Map<String, dynamic>> ref) async {
    final snapshot = await ref.get(const GetOptions(source: Source.server));
    if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    return snapshot;
  }

  void _checkOwner(
      DocumentSnapshot<Map<String, dynamic>> snapshot, PendingReport item) {
    if (snapshot.data()?['createdBy'] != item.userId ||
        snapshot.data()?['deletionInProgress'] == true) {
      throw StateError('El reporte no permite continuar este envío.');
    }
  }

  @override
  Future<void> ensureReport(PendingReport item) async {
    _checkAccount(item);
    final ref = _db.collection('reports').doc(item.id);
    try {
      final existing = await _fresh(ref);
      if (existing.exists) {
        _checkOwner(existing, item);
        return; // Never restore an old title, moderation decision or status.
      }
    } on FirebaseException catch (error) {
      // Current rules hide missing reports from residents. Creation still has to
      // pass those rules; a denied read is never interpreted as a confirmed save.
      if (error.code != 'permission-denied') rethrow;
    }
    try {
      _checkAccount(item);
      final profile = await _fresh(_db.collection('users').doc(item.userId));
      await ref.set({
        ...item.fields,
        'createdByName': profile.data()?['nombre'] ?? '',
        'createdBy': item.userId,
        'status': 'pendiente',
        'moderationStatus': 'pendiente',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      try {
        final existing = await _fresh(ref);
        if (existing.exists) {
          _checkOwner(existing, item);
          return;
        }
      } catch (_) {/* Preserve the write error and the local copy. */}
      rethrow;
    }
  }

  @override
  Future<void> ensurePhoto(PendingReport item, File photo) async {
    _checkAccount(item);
    final report = _db.collection('reports').doc(item.id);
    final parent = await _fresh(report);
    if (!parent.exists) throw StateError('El reporte ya no existe.');
    _checkOwner(parent, item);
    final metadataRef = report.collection('photos').doc(item.id);
    bool matches(DocumentSnapshot<Map<String, dynamic>> snapshot) =>
        snapshot.exists &&
        snapshot.data()?['uploadedBy'] == item.userId &&
        snapshot.data()?['storagePath'] == item.photoStoragePath;
    final previous = await _fresh(metadataRef);
    if (previous.exists) {
      if (!matches(previous)) {
        throw StateError('La fotografía existente no coincide.');
      }
      return;
    }
    // Preserve the existing uploader's token refresh for Storage custom claims.
    _checkAccount(item);
    await _refreshAuth();
    _checkAccount(item);
    final reference = _files.ref(item.photoStoragePath);
    var exists = false;
    try {
      final metadata = await reference.getMetadata();
      if (metadata.customMetadata?['uploadedBy'] != item.userId ||
          metadata.customMetadata?['reportUploadId'] != item.id) {
        throw StateError('El archivo existente no coincide.');
      }
      exists = true;
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') rethrow;
    }
    if (!exists) {
      _checkAccount(item);
      await FileService.validateLocalFileFormat(item.photoName!, photo.path);
      await reference.putFile(
          photo,
          SettableMetadata(
            contentType: FileService.contentTypeForName(item.photoName!),
            customMetadata: {
              'uploadedBy': item.userId,
              'reportUploadId': item.id
            },
          ));
    }
    try {
      _checkAccount(item);
      await _registerAttachment({
        'collection': 'reports',
        'documentId': item.id,
        'kind': 'photos',
        'attachmentId': item.id,
        'storagePath': reference.fullPath,
        'name': item.photoName,
      });
    } catch (_) {
      try {
        if (matches(await _fresh(metadataRef))) return;
      } catch (_) {/* Retry later. */}
      rethrow;
    }
  }
}
