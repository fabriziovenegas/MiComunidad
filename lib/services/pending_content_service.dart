import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'content_delivery.dart';
import 'pending_content.dart';
import 'pending_send.dart';

export 'pending_content.dart';
export 'pending_send.dart';

class PendingContentService with WidgetsBindingObserver {
  PendingContentService(
      {Future<Directory> Function()? directory,
      String? Function()? currentUserId,
      String Function()? newId,
      ContentDelivery? delivery,
      this.foregroundWait = const Duration(seconds: 4),
      this.retryInterval = const Duration(seconds: 30)})
      : _directory = directory ?? _defaultDirectory,
        _currentUserId = currentUserId ?? _signedInUser,
        _newId = newId ??
            (() => FirebaseFirestore.instance.collection('projects').doc().id),
        _delivery = delivery ?? FirebaseContentDelivery();
  static final instance = PendingContentService();
  final Future<Directory> Function() _directory;
  final String? Function() _currentUserId;
  final String Function() _newId;
  final ContentDelivery _delivery;
  final Duration foregroundWait;
  final Duration retryInterval;
  final _changes = StreamController<void>.broadcast();
  final _submissions = <String, Future<PendingSendResult>>{};
  final _submissionBodies = <String, String>{};
  final _inFlight = <String, Future<PendingSendResult>>{};
  Timer? _timer;
  StreamSubscription<User?>? _auth;

  static String? _signedInUser() {
    final user = FirebaseAuth.instance.currentUser;
    return user == null || user.isAnonymous ? null : user.uid;
  }

  static Future<Directory> _defaultDirectory() async {
    final project = FirebaseFirestore.instance.app.options.projectId
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return Directory(
        '${(await getApplicationSupportDirectory()).path}/pending_content_v1/$project');
  }

  String newId() => _newId();
  void start() {
    if (_timer != null) return;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(retryInterval, (_) => _retrySafely());
    _auth =
        FirebaseAuth.instance.authStateChanges().listen((_) => _retrySafely());
    _retrySafely();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _auth?.cancel();
    _auth = null;
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

  Future<File> _file(String id) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) {
      throw const FormatException('Invalid identifier');
    }
    return File('${(await _directory()).path}/$id.json');
  }

  Future<PendingContent?> _read(String id) async {
    final file = await _file(id);
    try {
      if (!await file.exists()) return null;
      final item = PendingContent.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>);
      if (item.id != id) throw const FormatException('Mismatched identifier');
      return item;
    } on FileSystemException {
      if (!await file.exists()) return null;
      rethrow;
    }
  }

  Future<void> _write(PendingContent item) async {
    final file = await _file(item.id);
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(item.toJson()), flush: true);
    await temp.rename(file.path);
  }

  Future<List<PendingContent>> pendingFor(String userId) async {
    final root = await _directory();
    if (!await root.exists()) return [];
    final result = <PendingContent>[];
    for (final file in await root.list(followLinks: false).toList()) {
      if (file is! File || !file.path.endsWith('.json')) continue;
      final name = file.uri.pathSegments.last;
      try {
        final item = await _read(name.substring(0, name.length - 5));
        if (item != null && item.userId == userId && !item.sent) {
          result.add(item);
        }
      } on FormatException {
        /* An invalid entry cannot block other valid entries. */
      }
    }
    return result;
  }

  Stream<List<PendingContent>> watch(String userId) =>
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
  Future<PendingSendResult> submit(
      {required String id,
      required String collection,
      required String expectedUserId,
      required Map<String, dynamic> fields,
      String? parentId}) {
    // Own this ID before disk or network awaits. Form and worker share attempts.
    final proposed = PendingContent(
        id: id,
        collection: collection,
        userId: expectedUserId,
        fields: fields,
        parentId: parentId);
    proposed.validate();
    final existing = _submissions[id];
    final body = jsonEncode(proposed.toJson());
    if (existing != null) {
      if (_submissionBodies[id] != body) {
        throw StateError('Este envío ya contiene otros datos.');
      }
      return existing;
    }
    _submissionBodies[id] = body;
    final operation = Future<PendingSendResult>(() async {
      try {
        if (_currentUserId() != expectedUserId) {
          throw StateError('La cuenta del envío cambió.');
        }
        var item = await _read(id);
        if (item == null) {
          await _write(proposed);
          item = proposed;
          _changes.add(null);
        } else if (item.path != proposed.path ||
            item.userId != expectedUserId ||
            jsonEncode(item.toJson()['fields']) !=
                jsonEncode(proposed.toJson()['fields'])) {
          throw StateError('Este envío ya contiene otros datos.');
        }
        if (item.sent) return const PendingSendResult(PendingSendState.sent);
        return await _attempt(item).timeout(foregroundWait,
            onTimeout: () => const PendingSendResult(PendingSendState.queued));
      } finally {
        _submissions.remove(id);
        _submissionBodies.remove(id);
      }
    });
    _submissions[id] = operation;
    return operation;
  }

  Future<PendingSendResult> _attempt(PendingContent item) =>
      _inFlight.putIfAbsent(
          item.id,
          () => Future(() async {
                try {
                  if (_currentUserId() != item.userId) {
                    return const PendingSendResult(PendingSendState.queued);
                  }
                  await _delivery.deliver(item);
                  item.sent = true;
                  item.blocked = false;
                  item.reason = null;
                  await _write(item);
                  try {
                    final file = await _file(item.id);
                    if (await file.exists()) await file.delete();
                  } catch (_) {
                    /* Sent marker prevents resending after cleanup failure. */
                  }
                  _changes.add(null);
                  return const PendingSendResult(PendingSendState.sent);
                } catch (error) {
                  item.blocked = !pendingFailureIsTemporary(error);
                  item.reason =
                      item.blocked ? pendingFailureReason(error) : null;
                  try {
                    await _write(item);
                  } catch (_) {/* Retain previous durable entry. */}
                  _changes.add(null);
                  return PendingSendResult(
                      item.blocked
                          ? PendingSendState.blocked
                          : PendingSendState.queued,
                      reason: item.reason);
                } finally {
                  _inFlight.remove(item.id);
                }
              }));
  Future<void> processPending({bool retryBlocked = false}) async {
    final user = _currentUserId();
    if (user == null) return;
    for (final item in await pendingFor(user)) {
      if (_currentUserId() != user) break;
      if (item.blocked && !retryBlocked) continue;
      await _attempt(item).timeout(foregroundWait,
          onTimeout: () => const PendingSendResult(PendingSendState.queued));
    }
  }
}
