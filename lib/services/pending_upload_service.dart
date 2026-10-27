import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'file_service.dart';
import 'attachment_delivery.dart';
import 'pending_send.dart';
import 'upload_connection.dart';

class UploadSendResult extends PendingSendResult {
  const UploadSendResult(super.state, {super.reason, this.error});
  final Object? error;
}

class PendingUploadService with WidgetsBindingObserver {
  PendingUploadService({
    AttachmentDelivery? delivery,
    String? Function()? currentUserId,
    Future<Directory> Function()? supportDirectory,
    String Function()? projectId,
    Future<bool> Function()? isOffline,
    this.foregroundWait = const Duration(seconds: 4),
  })  : _delivery = delivery ?? FirebaseAttachmentDelivery(),
        _currentUserId = currentUserId ?? _signedInUser,
        _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
        _isOffline = isOffline ?? (() => UploadConnection.isOffline()),
        _projectId = projectId ?? (() => Firebase.app().options.projectId);
  static final PendingUploadService instance = PendingUploadService();

  final AttachmentDelivery _delivery;
  final String? Function() _currentUserId;
  final Future<Directory> Function() _supportDirectory;
  final String Function() _projectId;
  final Future<bool> Function() _isOffline;
  final Duration foregroundWait;
  final _changes = StreamController<void>.broadcast();
  StreamSubscription<User?>? _auth;
  StreamSubscription<bool?>? _connection;
  final Map<String, Future<void>> _inFlight = {};
  final Map<String, Future<UploadSendResult>> _attempts = {};
  Future<void> _queueTail = Future<void>.value();

  static String? _signedInUser() {
    final user = FirebaseAuth.instance.currentUser;
    return user == null || user.isAnonymous ? null : user.uid;
  }

  // Serialize read/modify/write of preferences, without holding up network I/O.
  Future<T> _withQueueLock<T>(Future<T> Function() action) {
    final result = _queueTail.then((_) => action());
    _queueTail =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  static const _storageKey = 'pending_community_uploads_v1';
  Timer? _timer;
  bool _processing = false;

  void start() {
    if (_timer != null) return;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _retrySafely(),
    );
    _auth = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && !user.isAnonymous) _retrySafely();
    });
    _connection = UploadConnection.changes.listen((offline) {
      if (offline == false) _retrySafely();
    }, onError: (Object _) {
      // A missing native listener leaves periodic/in-app retries available.
    });
    _retrySafely();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _auth?.cancel();
    _auth = null;
    _connection?.cancel();
    _connection = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _retrySafely();
  }

  Future<void> _retrySafely() async {
    try {
      await processPending();
    } catch (_) {}
  }

  Future<List<PendingAttachment>> pendingFor(String userId) async =>
      (await _withQueueLock(_load))
          .where((item) =>
              item.userId == userId &&
              (item.projectId == null || item.projectId == _projectId()) &&
              !item.completed)
          .toList();
  Stream<List<PendingAttachment>> watch(String userId) =>
      Stream.multi((controller) {
        var active = true;
        var tail = Future<void>.value();
        void update() {
          tail = tail.then((_) async {
            if (!active) return;
            try {
              final items = await pendingFor(userId);
              if (active) controller.add(items);
            } catch (e, s) {
              if (active) controller.addError(e, s);
            }
          });
        }

        final sub = _changes.stream.listen((_) => update());
        controller.onCancel = () {
          active = false;
          return sub.cancel();
        };
        update();
      });

  Future<bool> uploadOrQueue({
    required String collection,
    required String documentId,
    required String kind,
    required SelectedUpload selected,
  }) async {
    final result = await send(
        collection: collection,
        documentId: documentId,
        kind: kind,
        selected: selected);
    if (result.state == PendingSendState.blocked) {
      throw result.error ??
          StateError(result.reason ?? 'No se pudo subir el archivo.');
    }
    return result.state == PendingSendState.queued;
  }

  Future<UploadSendResult> send(
      {required String collection,
      required String documentId,
      required String kind,
      required SelectedUpload selected}) async {
    final userId = _currentUserId();
    if (userId == null) {
      throw const FileUploadException(
          'Debes iniciar sesión para subir archivos.');
    }
    final item = await _persist(
        collection: collection,
        documentId: documentId,
        kind: kind,
        selected: selected,
        userId: userId);
    // Keep waiting for a slow connected upload. Only a connectivity check or a
    // real delivery failure may move it out of the foreground uploading state.
    return _attempt(item);
  }

  Future<bool> _offline() async {
    try {
      return await _isOffline()
          .timeout(const Duration(seconds: 6), onTimeout: () => false);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _status(PendingAttachment item,
          {required bool waitingForConnection,
          bool blocked = false,
          String? reason}) =>
      _withQueueLock(() async {
        final items = await _load();
        final matches = items.where((entry) => entry.id == item.id);
        if (matches.isEmpty || matches.first.completed) return false;
        await _save(items
            .map((entry) => entry.id == item.id
                ? PendingAttachment.fromJson({
                    ...entry.toJson(),
                    'waitingForConnection': waitingForConnection,
                    'blocked': blocked,
                    'reason': reason
                  })
                : entry)
            .toList());
        return true;
      });

  Future<UploadSendResult> _attempt(PendingAttachment item) {
    final previous = _attempts[item.id];
    if (previous != null) return previous;
    late final Future<UploadSendResult> operation;
    operation = Future<UploadSendResult>(() async {
      try {
        return await _waitForDelivery(item);
      } finally {
        if (identical(_attempts[item.id], operation)) _attempts.remove(item.id);
      }
    });
    _attempts[item.id] = operation;
    return operation;
  }

  Future<UploadSendResult> _waitForDelivery(PendingAttachment item) async {
    if (!item.completed && await _offline()) {
      final retained = await _status(item, waitingForConnection: true);
      return UploadSendResult(
          retained ? PendingSendState.queued : PendingSendState.sent);
    }
    await _status(item, waitingForConnection: false);
    UploadSendResult? settled;
    // This outcome remains observed even if the screen returns an offline
    // result while the Firebase SDK still has a reconnecting request in flight.
    final outcome = _perform(item).then((value) {
      settled = value;
      return value;
    }, onError: (Object error, StackTrace stack) {
      final value = UploadSendResult(PendingSendState.blocked,
          reason: pendingFailureReason(error), error: error);
      settled = value;
      return value;
    });
    while (true) {
      final result = await outcome
          .then<UploadSendResult?>((value) => value)
          .timeout(foregroundWait, onTimeout: () => null);
      if (result != null) return result;
      if (await _offline()) {
        if (settled != null) return settled!;
        final retained = await _status(item, waitingForConnection: true);
        if (settled != null) return settled!;
        return UploadSendResult(
            retained ? PendingSendState.queued : PendingSendState.sent);
      }
    }
  }

  Future<UploadSendResult> _perform(PendingAttachment item) async {
    try {
      await _deliverOnce(item);
      return const UploadSendResult(PendingSendState.sent);
    } catch (error) {
      final blocked = !pendingFailureIsTemporary(error);
      final offline = !blocked && await _offline();
      final reason = blocked
          ? pendingFailureReason(error)
          : offline
              ? null
              : 'No se pudo completar la subida. Reintenta en unos momentos.';
      await _status(item,
          waitingForConnection: offline, blocked: blocked, reason: reason);
      return UploadSendResult(
          blocked ? PendingSendState.blocked : PendingSendState.queued,
          reason: reason,
          error: error);
    }
  }

  Future<void> processPending({bool retryBlocked = false}) async {
    if (_processing) return;
    final current = _currentUserId();
    if (current == null) return;
    _processing = true;
    try {
      final items = (await _withQueueLock(_load)).where((item) =>
          item.userId == current &&
          (item.projectId == null || item.projectId == _projectId()));
      for (final item in items) {
        if (_currentUserId() != current) break;
        if (item.blocked && !item.completed && !retryBlocked) continue;
        await _attempt(item).timeout(foregroundWait,
            onTimeout: () => const UploadSendResult(PendingSendState.queued));
      }
    } finally {
      _processing = false;
    }
  }

  Future<PendingAttachment> _persist({
    required String collection,
    required String documentId,
    required String kind,
    required SelectedUpload selected,
    required String userId,
  }) async {
    if (!const ['projects', 'reports', 'events'].contains(collection) ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(documentId) ||
        !(kind == 'photos' || (collection == 'events' && kind == 'minutes'))) {
      throw const FileUploadException('El destino del archivo no es válido.');
    }
    final extension = selected.name.split('.').last.toLowerCase();
    final limit = kind == 'minutes'
        ? FileService.maxDocumentBytes
        : FileService.maxImageBytes;
    if (!(kind == 'minutes'
            ? FileService.documentExtensions
            : FileService.imageExtensions)
        .contains(extension)) {
      throw const FileUploadException('El formato del archivo no es válido.');
    }
    final bytes = selected.file.bytes;
    final sourcePath = selected.file.path;
    if (sourcePath == null && bytes == null) {
      throw const FileUploadException(
        'No se pudo conservar el archivo para reintentar la carga.',
      );
    }
    final size = bytes?.length ?? await File(sourcePath!).length();
    if (size > limit) {
      throw FileUploadException(
          'El archivo no puede superar ${limit ~/ (1024 * 1024)} MB.');
    }
    final project = _projectId();
    final directory = Directory(
      '${(await _supportDirectory()).path}${Platform.pathSeparator}pending_uploads${Platform.pathSeparator}${project.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}',
    );
    await directory.create(recursive: true);
    final safeName = selected.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final random = Random.secure();
    final id = List.generate(
            16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
    final saved =
        File('${directory.path}${Platform.pathSeparator}${id}_$safeName');
    if (bytes != null) {
      await saved.writeAsBytes(bytes, flush: true);
    } else {
      await File(sourcePath!).copy(saved.path);
      final handle = await saved.open(mode: FileMode.append);
      await handle.flush();
      await handle.close();
    }
    if (_currentUserId() != userId) {
      throw StateError('La cuenta del envío cambió.');
    }
    final item = PendingAttachment(
      id: id,
      collection: collection,
      documentId: documentId,
      kind: kind,
      localPath: saved.path,
      name: selected.name,
      userId: userId,
      projectId: project,
      waitingForConnection: false,
    );
    await _withQueueLock(() async {
      final items = await _load()
        ..add(item);
      await _save(items);
    });
    return item;
  }

  Future<void> _deliverOnce(PendingAttachment item) {
    final existing = _inFlight[item.id];
    if (existing != null) return existing;
    final operation = Future<void>(() async {
      try {
        // A background snapshot may still contain an item already completed by
        // the foreground. Consult the queue again before touching the network.
        final current = await _withQueueLock(() async {
          final matches = (await _load()).where((entry) => entry.id == item.id);
          return matches.isEmpty ? null : matches.first;
        });
        if (current == null) return;
        if (_currentUserId() != current.userId) {
          throw StateError('La cuenta del envío cambió.');
        }
        if (current.projectId != null && current.projectId != _projectId()) {
          throw StateError('El proyecto del envío cambió.');
        }
        if (!current.completed) {
          await _delivery.deliver(current);
          await _withQueueLock(() async {
            final items = await _load();
            await _save(items
                .map((entry) => entry.id == current.id
                    ? PendingAttachment.fromJson(
                        {...entry.toJson(), 'completed': true})
                    : entry)
                .toList());
          });
        }
        await _remove(current);
      } finally {
        _inFlight.remove(item.id);
      }
    });
    _inFlight[item.id] = operation;
    return operation;
  }

  Future<List<PendingAttachment>> _load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List)
        .map((value) =>
            PendingAttachment.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  Future<void> _save(List<PendingAttachment> items) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _storageKey,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
    if (!saved) {
      throw const FileSystemException(
          'No se pudo guardar el adjunto pendiente.');
    }
    _changes.add(null);
  }

  Future<void> _remove(PendingAttachment item) async {
    await _withQueueLock(() async {
      final items = await _load()
        ..removeWhere((value) => value.id == item.id);
      await _save(items);
    });
    final file = File(item.localPath);
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // The cloud save is confirmed; a local cleanup error is not a failed upload.
    }
  }
}
