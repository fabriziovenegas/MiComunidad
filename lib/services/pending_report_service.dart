import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'file_service.dart';
import 'report_delivery.dart';

enum ReportSendState { sent, queued, blocked }

class ReportSendResult {
  const ReportSendResult(this.state, {this.reportConfirmed = false});
  final ReportSendState state;
  final bool reportConfirmed;
}

/// The manifest is published only after the optional photo is copied and flushed.
/// Pending records are isolated by Firebase project and by the submitting account.
class PendingReport {
  PendingReport({
    required this.id,
    required this.userId,
    required Map<String, String> fields,
    this.photoName,
    this.reportConfirmed = false,
    this.blocked = false,
    this.sent = false,
  }) : fields = Map.unmodifiable(fields);

  final String id;
  final String userId;
  final Map<String, String> fields;
  final String? photoName;
  bool reportConfirmed;
  bool blocked;
  bool sent;

  String get photoStoragePath =>
      'reports/$id/photos/${id}_photo.${photoName!.split('.').last.toLowerCase()}';

  Map<String, dynamic> toJson() => {
        'version': 1,
        'id': id,
        'userId': userId,
        'fields': fields,
        'photoName': photoName,
        'reportConfirmed': reportConfirmed,
        'blocked': blocked,
        'sent': sent,
      };

  factory PendingReport.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) throw const FormatException('Unknown outbox');
    return PendingReport(
      id: json['id'] as String,
      userId: json['userId'] as String,
      fields: Map<String, String>.from(json['fields'] as Map),
      photoName: json['photoName'] as String?,
      reportConfirmed: json['reportConfirmed'] == true,
      blocked: json['blocked'] == true,
      sent: json['sent'] == true,
    );
  }
}

class PendingReportService with WidgetsBindingObserver {
  PendingReportService({
    Future<Directory> Function()? directory,
    String? Function()? currentUserId,
    String Function()? newId,
    ReportDelivery? delivery,
    this.foregroundWait = const Duration(seconds: 4),
    this.retryInterval = const Duration(seconds: 30),
  })  : _directory = directory ?? _defaultDirectory,
        _currentUserId = currentUserId ?? _signedInUser,
        _newId = newId ??
            (() => FirebaseFirestore.instance.collection('reports').doc().id),
        _delivery = delivery ?? FirebaseReportDelivery();

  static final instance = PendingReportService();
  final Future<Directory> Function() _directory;
  final String? Function() _currentUserId;
  final String Function() _newId;
  final ReportDelivery _delivery;
  final Duration foregroundWait;
  final Duration retryInterval;
  final _changes = StreamController<void>.broadcast();
  final _submissions = <String, Future<ReportSendResult>>{};
  final _inFlight = <String, Future<ReportSendResult>>{};
  Timer? _timer;
  StreamSubscription<User?>? _auth;

  static String? _signedInUser() {
    final user = FirebaseAuth.instance.currentUser;
    return user == null || user.isAnonymous ? null : user.uid;
  }

  static Future<Directory> _defaultDirectory() async {
    final project = FirebaseFirestore.instance.app.options.projectId;
    final safeProject = project.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return Directory('${(await getApplicationSupportDirectory()).path}'
        '${Platform.pathSeparator}pending_reports_v1${Platform.pathSeparator}$safeProject');
  }

  String newReportId() => _newId();

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
    } catch (_) {
      // Disk/network errors leave durable entries in place for the next retry.
    }
  }

  void _notify() => _changes.add(null);

  Future<Directory> _folder(String id) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) {
      throw const FormatException('Invalid report identifier');
    }
    return Directory(
        '${(await _directory()).path}${Platform.pathSeparator}$id');
  }

  Future<File> _manifest(String id) async =>
      File('${(await _folder(id)).path}${Platform.pathSeparator}report.json');

  Future<PendingReport?> _read(String id) async {
    final file = await _manifest(id);
    if (!await file.exists()) return null;
    late final PendingReport result;
    try {
      result = PendingReport.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    } on FileSystemException {
      // A successful sender may clean up between exists() and readAsString().
      if (!await file.exists()) return null;
      rethrow;
    }
    if (result.id != id) {
      throw const FormatException('Mismatched report identifier');
    }
    return result;
  }

  Future<void> _write(PendingReport item) async {
    final file = await _manifest(item.id);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(item.toJson()), flush: true);
    await temporary.rename(file.path);
  }

  Future<File> photoFile(String id) async =>
      File('${(await _folder(id)).path}${Platform.pathSeparator}photo');

  Future<List<PendingReport>> pendingFor(String userId) async {
    final root = await _directory();
    if (!await root.exists()) return [];
    final result = <PendingReport>[];
    // Finish directory enumeration before reading/removing per-report files.
    for (final entity in await root.list(followLinks: false).toList()) {
      if (entity is! Directory) continue;
      final id = entity.uri.pathSegments.where((part) => part.isNotEmpty).last;
      final item = await _read(id);
      if (item != null && item.userId == userId && !item.sent) result.add(item);
    }
    return result;
  }

  Stream<List<PendingReport>> watch(String userId) =>
      Stream.multi((controller) {
        var active = true;
        var refresh = Future<void>.value();
        void update() {
          refresh = refresh.then((_) async {
            if (!active) return;
            try {
              final items = await pendingFor(userId);
              if (active) controller.add(items);
            } catch (error, stack) {
              if (active) controller.addError(error, stack);
            }
          });
        }

        // Subscribe before the first disk read so a quick save cannot be missed.
        final subscription = _changes.stream.listen((_) => update());
        controller.onCancel = () {
          active = false;
          return subscription.cancel();
        };
        update();
      });

  Future<ReportSendResult> submit({
    required String id,
    required String expectedUserId,
    required Map<String, String> fields,
    SelectedUpload? image,
  }) {
    // The form and background worker share this same entry and network attempt.
    return _submissions.putIfAbsent(
        id,
        () => Future(() async {
              try {
                if (_currentUserId() != expectedUserId) {
                  throw StateError('Account changed');
                }
                var item = await _read(id);
                if (item == null) {
                  final folder = await _folder(id);
                  await folder.create(recursive: true);
                  if (image != null) {
                    final extension = image.name.split('.').last.toLowerCase();
                    if (!FileService.imageExtensions.contains(extension)) {
                      throw const FileUploadException(
                          'Selecciona una imagen JPG, JPEG, PNG o WEBP.');
                    }
                    final file = await photoFile(id);
                    final bytes = image.file.bytes;
                    if (bytes != null) {
                      if (bytes.length > FileService.maxImageBytes) {
                        throw const FileUploadException(
                            'La imagen no puede superar 10 MB.');
                      }
                      await file.writeAsBytes(bytes, flush: true);
                    } else {
                      final source = image.file.path;
                      if (source == null) {
                        throw const FileUploadException(
                            'No se pudo conservar la imagen.');
                      }
                      if (await File(source).length() >
                          FileService.maxImageBytes) {
                        throw const FileUploadException(
                            'La imagen no puede superar 10 MB.');
                      }
                      await File(source).copy(file.path);
                      final handle = await file.open(mode: FileMode.append);
                      await handle.flush();
                      await handle.close();
                    }
                  }
                  if (_currentUserId() != expectedUserId) {
                    throw StateError('Account changed');
                  }
                  item = PendingReport(
                      id: id,
                      userId: expectedUserId,
                      fields: fields,
                      photoName: image?.name);
                  await _write(item);
                  _notify();
                } else if (item.userId != expectedUserId ||
                    jsonEncode(item.fields) != jsonEncode(fields) ||
                    item.photoName != image?.name) {
                  throw StateError(
                      'This pending report already has different content');
                }
                if (item.sent) {
                  return const ReportSendResult(ReportSendState.sent,
                      reportConfirmed: true);
                }
                return await _attempt(item).timeout(foregroundWait,
                    onTimeout: () => ReportSendResult(ReportSendState.queued,
                        reportConfirmed: item!.reportConfirmed));
              } finally {
                _submissions.remove(id);
              }
            }));
  }

  Future<ReportSendResult> _attempt(PendingReport item) =>
      _inFlight.putIfAbsent(
          item.id,
          () => Future(() async {
                try {
                  if (_currentUserId() != item.userId) {
                    return ReportSendResult(ReportSendState.queued,
                        reportConfirmed: item.reportConfirmed);
                  }
                  if (!item.reportConfirmed) {
                    await _delivery.ensureReport(item);
                    item.reportConfirmed = true;
                    await _write(item);
                    _notify();
                  }
                  if (_currentUserId() != item.userId) {
                    return ReportSendResult(ReportSendState.queued,
                        reportConfirmed: true);
                  }
                  if (item.photoName != null) {
                    await _delivery.ensurePhoto(item, await photoFile(item.id));
                  }
                  item.sent = true;
                  item.blocked = false;
                  await _write(item);
                  // A cleanup failure must never turn a confirmed delivery into a resend.
                  try {
                    await _cleanup(item.id);
                  } catch (_) {/* Retain sent manifest. */}
                  _notify();
                  return const ReportSendResult(ReportSendState.sent,
                      reportConfirmed: true);
                } catch (error) {
                  item.blocked = error is FileSystemException ||
                      error is StateError ||
                      error is FormatException ||
                      (error is FirebaseException &&
                          ![
                            'unavailable',
                            'deadline-exceeded',
                            'network-request-failed',
                            'retry-limit-exceeded',
                            'unknown',
                            'canceled',
                            'aborted',
                          ].contains(error.code));
                  try {
                    await _write(item);
                  } catch (_) {/* Keep previous manifest. */}
                  _notify();
                  return ReportSendResult(
                      item.blocked
                          ? ReportSendState.blocked
                          : ReportSendState.queued,
                      reportConfirmed: item.reportConfirmed);
                } finally {
                  _inFlight.remove(item.id);
                }
              }));

  Future<void> processPending({bool retryBlocked = false}) async {
    final userId = _currentUserId();
    if (userId == null) return;
    for (final item in await pendingFor(userId)) {
      if (_currentUserId() != userId) break;
      if (item.blocked && !retryBlocked) continue;
      await _attempt(item).timeout(foregroundWait,
          onTimeout: () => ReportSendResult(ReportSendState.queued,
              reportConfirmed: item.reportConfirmed));
    }
  }

  Future<void> _cleanup(String id) async {
    // Only named files in the validated per-report directory; no recursive delete.
    for (final file in [await photoFile(id), await _manifest(id)]) {
      if (await file.exists()) await file.delete();
    }
    await (await _folder(id)).delete();
  }
}
