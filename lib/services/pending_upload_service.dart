import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'file_service.dart';

class PendingUploadService {
  PendingUploadService._();
  static final PendingUploadService instance = PendingUploadService._();

  static const _storageKey = 'pending_community_uploads_v1';
  Timer? _timer;
  bool _processing = false;

  void start() {
    _timer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => processPending(),
    );
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && !user.isAnonymous) processPending();
    });
  }

  Future<bool> uploadOrQueue({
    required String collection,
    required String documentId,
    required String kind,
    required SelectedUpload selected,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw const FileUploadException(
          'Debes iniciar sesión para subir archivos.');
    }
    final item = await _persist(
      collection: collection,
      documentId: documentId,
      kind: kind,
      selected: selected,
      userId: user.uid,
    );
    try {
      await _upload(item);
      await _remove(item);
      return false;
    } on FirebaseException catch (error) {
      if (error.code == 'unauthorized' || error.code == 'permission-denied') {
        await _remove(item);
        rethrow;
      }
      return true;
    } on SocketException {
      return true;
    }
  }

  Future<void> processPending() async {
    if (_processing) return;
    final current = FirebaseAuth.instance.currentUser;
    if (current == null || current.isAnonymous) return;
    _processing = true;
    try {
      final items = await _load();
      for (final item in items.where((value) => value.userId == current.uid)) {
        try {
          await _upload(item);
          await _remove(item);
        } on FirebaseException catch (error) {
          if (error.code == 'unauthorized' ||
              error.code == 'permission-denied') {
            await _remove(item);
          }
        } on SocketException {
          break;
        }
      }
    } finally {
      _processing = false;
    }
  }

  Future<_PendingUpload> _persist({
    required String collection,
    required String documentId,
    required String kind,
    required SelectedUpload selected,
    required String userId,
  }) async {
    final sourcePath = selected.file.path;
    if (sourcePath == null) {
      throw const FileUploadException(
        'No se pudo conservar el archivo para reintentar la carga.',
      );
    }
    final directory = Directory(
      '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}pending_uploads',
    );
    await directory.create(recursive: true);
    final safeName = selected.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final id = '${DateTime.now().microsecondsSinceEpoch}_$userId';
    final saved = await File(sourcePath).copy(
      '${directory.path}${Platform.pathSeparator}${id}_$safeName',
    );
    final item = _PendingUpload(
      id: id,
      collection: collection,
      documentId: documentId,
      kind: kind,
      localPath: saved.path,
      name: selected.name,
      userId: userId,
    );
    final items = await _load()
      ..add(item);
    await _save(items);
    return item;
  }

  Future<void> _upload(_PendingUpload item) async {
    final selected = SelectedUpload(
      PlatformFile(
        name: item.name,
        path: item.localPath,
        size: await File(item.localPath).length(),
      ),
    );
    final uploaded = await FileService.upload(
      selected: selected,
      folder: '${item.collection}/${item.documentId}/${item.kind}',
      uploadedBy: item.userId,
    );
    await FirebaseFirestore.instance
        .collection(item.collection)
        .doc(item.documentId)
        .collection(item.kind)
        .add({
      'url': uploaded.url,
      'storagePath': uploaded.storagePath,
      'name': item.name,
      'contentType': item.name.toLowerCase().endsWith('.pdf')
          ? 'application/pdf'
          : 'image',
      'uploadedBy': item.userId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<_PendingUpload>> _load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List)
        .map((value) => _PendingUpload.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  Future<void> _save(List<_PendingUpload> items) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> _remove(_PendingUpload item) async {
    final items = await _load()
      ..removeWhere((value) => value.id == item.id);
    await _save(items);
    final file = File(item.localPath);
    if (await file.exists()) await file.delete();
  }
}

class _PendingUpload {
  const _PendingUpload({
    required this.id,
    required this.collection,
    required this.documentId,
    required this.kind,
    required this.localPath,
    required this.name,
    required this.userId,
  });

  final String id;
  final String collection;
  final String documentId;
  final String kind;
  final String localPath;
  final String name;
  final String userId;

  factory _PendingUpload.fromJson(Map<String, dynamic> json) => _PendingUpload(
        id: json['id'] as String,
        collection: json['collection'] as String,
        documentId: json['documentId'] as String,
        kind: json['kind'] as String,
        localPath: json['localPath'] as String,
        name: json['name'] as String,
        userId: json['userId'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'collection': collection,
        'documentId': documentId,
        'kind': kind,
        'localPath': localPath,
        'name': name,
        'userId': userId,
      };
}
