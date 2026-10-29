import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/report_edit.dart';
import 'file_service.dart';
import 'attachment_registry.dart';

/// One contribution keeps the same identity across retries and app restarts.
class PendingAttachment {
  const PendingAttachment({
    required this.id,
    required this.collection,
    required this.documentId,
    required this.kind,
    required this.localPath,
    required this.name,
    required this.userId,
    this.completed = false,
    this.blocked = false,
    this.waitingForConnection = true,
    this.reason,
    this.projectId,
  });

  final String id;
  final String collection;
  final String documentId;
  final String kind;
  final String localPath;
  final String name;
  final String userId;
  final bool completed;
  final bool blocked;
  final bool waitingForConnection;
  final String? reason;
  final String? projectId;

  String get metadataPath => '$collection/$documentId/$kind/$id';
  String get storagePath =>
      '$collection/$documentId/$kind/${id}_${name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}';

  factory PendingAttachment.fromJson(Map<String, dynamic> json) =>
      PendingAttachment(
        id: json['id'] as String,
        collection: json['collection'] as String,
        documentId: json['documentId'] as String,
        kind: json['kind'] as String,
        localPath: json['localPath'] as String,
        name: json['name'] as String,
        userId: json['userId'] as String,
        completed: json['completed'] == true,
        blocked: json['blocked'] == true,
        waitingForConnection: json['waitingForConnection'] != false,
        reason: json['reason'] as String?,
        projectId: json['projectId'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'collection': collection,
        'documentId': documentId,
        'kind': kind,
        'localPath': localPath,
        'name': name,
        'userId': userId,
        'completed': completed,
        'blocked': blocked,
        'waitingForConnection': waitingForConnection,
        'reason': reason,
        'projectId': projectId,
      };
}

abstract class AttachmentDelivery {
  Future<void> deliver(PendingAttachment item);
}

class FirebaseAttachmentDelivery implements AttachmentDelivery {
  FirebaseAttachmentDelivery({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    String? Function()? currentUserId,
    Future<void> Function()? refreshAuth,
    Future<void> Function(Map<String, dynamic>)? registerAttachment,
  })  : _firestore = firestore,
        _storage = storage,
        _currentUserId = currentUserId ?? _signedInUser,
        _refreshAuth = refreshAuth ?? _refreshToken,
        _registerAttachment = registerAttachment ?? AttachmentRegistry.register;

  final FirebaseFirestore? _firestore;
  final FirebaseStorage? _storage;
  final String? Function() _currentUserId;
  final Future<void> Function() _refreshAuth;
  final Future<void> Function(Map<String, dynamic>) _registerAttachment;

  static String? _signedInUser() {
    final user = FirebaseAuth.instance.currentUser;
    return user == null || user.isAnonymous ? null : user.uid;
  }

  static Future<void> _refreshToken() async {
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
  }

  void _checkAccount(PendingAttachment item) {
    if (_currentUserId() != item.userId) {
      throw StateError('La cuenta del envío cambió.');
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _fresh(
      DocumentReference<Map<String, dynamic>> reference) async {
    final snapshot =
        await reference.get(const GetOptions(source: Source.server));
    if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    return snapshot;
  }

  bool _matches(DocumentSnapshot<Map<String, dynamic>> snapshot,
          PendingAttachment item) =>
      snapshot.exists &&
      snapshot.data()?['uploadedBy'] == item.userId &&
      snapshot.data()?['storagePath'] == item.storagePath &&
      snapshot.data()?['uploadId'] == item.id;

  Future<bool> _objectExists(
      Reference reference, PendingAttachment item) async {
    try {
      final metadata = await reference.getMetadata();
      if (metadata.customMetadata?['uploadedBy'] != item.userId ||
          metadata.customMetadata?['attachmentUploadId'] != item.id) {
        throw StateError('El archivo existente no coincide con este envío.');
      }
      return true;
    } on FirebaseException catch (error) {
      if (error.code == 'object-not-found') return false;
      rethrow;
    }
  }

  @override
  Future<void> deliver(PendingAttachment item) async {
    _checkAccount(item);
    final parentRef = (_firestore ?? FirebaseFirestore.instance)
        .collection(item.collection)
        .doc(item.documentId);
    final parent = await _fresh(parentRef);
    final data = parent.data();
    if (!parent.exists) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'not-found');
    }
    if (data?['deletionInProgress'] == true ||
        (item.collection == 'projects' && data?['isTrashed'] != false) ||
        (item.collection == 'reports' &&
            !(reportContentIsEditable(data!) &&
                (data['moderationStatus'] == 'aprobado' ||
                    data['createdBy'] == item.userId)))) {
      throw FirebaseException(
          plugin: 'cloud_firestore', code: 'permission-denied');
    }
    final metadataRef = parentRef.collection(item.kind).doc(item.id);
    final existing = await _fresh(metadataRef);
    if (existing.exists) {
      if (!_matches(existing, item)) {
        throw StateError('El adjunto existente no coincide con este envío.');
      }
      return;
    }

    await _refreshAuth();
    _checkAccount(item);
    final reference =
        (_storage ?? FirebaseStorage.instance).ref(item.storagePath);
    if (!await _objectExists(reference, item)) {
      _checkAccount(item);
      final file = File(item.localPath);
      await file.length();
      await FileService.validateLocalFileFormat(item.name, item.localPath);
      try {
        await reference.putFile(
          file,
          SettableMetadata(
            contentType: FileService.contentTypeForName(item.name),
            customMetadata: {
              'uploadedBy': item.userId,
              'attachmentUploadId': item.id,
            },
          ),
        );
      } catch (_) {
        // A lost acknowledgement must not cause another object to be created.
        try {
          _checkAccount(item);
          if (!await _objectExists(reference, item)) rethrow;
        } catch (_) {
          rethrow;
        }
      }
    }
    _checkAccount(item);
    try {
      await _registerAttachment({
        'collection': item.collection,
        'documentId': item.documentId,
        'kind': item.kind,
        'attachmentId': item.id,
        'storagePath': item.storagePath,
        'name': item.name,
      });
    } catch (_) {
      // Existing rules forbid updates. Recover a completed create by reading it.
      try {
        _checkAccount(item);
        if (_matches(await _fresh(metadataRef), item)) return;
      } catch (_) {/* Keep the original failure and the local copy. */}
      rethrow;
    }
  }
}
