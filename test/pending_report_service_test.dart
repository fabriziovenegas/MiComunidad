import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:micomunidad/services/file_service.dart';
import 'package:micomunidad/services/pending_report_service.dart';
import 'package:micomunidad/services/report_delivery.dart';

const reportFields = {
  'title': 'Foco de la plaza',
  'description': 'La luz no enciende por la noche.',
  'location': 'Plaza del barrio ficticio',
  'category': 'iluminacion',
  'priority': 'media',
  'createdByName': 'Persona de prueba',
};

class LocalDelivery implements ReportDelivery {
  final reports = <String, Map<String, String>>{};
  final photos = <String, List<int>>{};
  int reportCalls = 0;
  int photoCalls = 0;
  Future<void> Function(PendingReport)? beforeReport;
  Future<void> Function(PendingReport)? beforePhoto;

  @override
  Future<void> ensureReport(PendingReport item) async {
    reportCalls++;
    await beforeReport?.call(item);
    reports.putIfAbsent(item.id, () => Map.of(item.fields));
  }

  @override
  Future<void> ensurePhoto(PendingReport item, File file) async {
    photoCalls++;
    await beforePhoto?.call(item);
    if (!photos.containsKey(item.photoStoragePath)) {
      photos[item.photoStoragePath] = await file.readAsBytes();
    }
  }
}

FirebaseException noConnection() =>
    FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');

void main() {
  late Directory temporary;
  late Directory outbox;
  late LocalDelivery delivery;
  late String? user;
  PendingReportService service({Duration wait = const Duration(seconds: 1)}) =>
      PendingReportService(
        directory: () async => outbox,
        currentUserId: () => user,
        newId: () => 'stable-report',
        delivery: delivery,
        foregroundWait: wait,
      );
  Future<SelectedUpload> photo() async {
    final file = File('${temporary.path}/original.png');
    await file.writeAsBytes([137, 80, 78, 71, 1, 2, 3]);
    return SelectedUpload(
        PlatformFile(name: 'original.png', path: file.path, size: 7));
  }

  Future<ReportSendResult> submit(PendingReportService queue,
          {SelectedUpload? image, String id = 'stable-report'}) =>
      queue.submit(
        id: id,
        expectedUserId: 'owner',
        fields: reportFields,
        image: image,
      );
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('report-outbox-test-');
    outbox = Directory('${temporary.path}/outbox');
    delivery = LocalDelivery();
    user = 'owner';
  });
  tearDown(() async {
    // Delete only this test-owned absolute temporary directory after validation.
    final root = await temporary.resolveSymbolicLinks();
    expect(root, contains('report-outbox-test-'));
    await Directory(root).delete(recursive: true);
  });

  test('both report and flushed photo exist on disk before first network call',
      () async {
    final queue = service();
    final image = await photo();
    delivery.beforeReport = (item) async {
      expect((await queue.pendingFor('owner')).single.fields, reportFields);
      expect(await (await queue.photoFile(item.id)).readAsBytes(),
          [137, 80, 78, 71, 1, 2, 3]);
      throw noConnection();
    };
    expect((await submit(queue, image: image)).state, ReportSendState.queued);
    expect(delivery.reports, isEmpty);
  });

  test(
      'reopening restores report and copied photo even after original is deleted',
      () async {
    final image = await photo();
    delivery.beforeReport = (_) async => throw noConnection();
    expect(
        (await submit(service(), image: image)).state, ReportSendState.queued);
    await File(image.file.path!).delete();
    // A different service instance reads only durable files, no old state.
    final reopened = service();
    expect(
        (await reopened.pendingFor('owner')).single.photoName, 'original.png');
    delivery.beforeReport = null;
    await reopened.processPending();
    expect(delivery.reports.keys, ['stable-report']);
    expect(delivery.photos.values.single, [137, 80, 78, 71, 1, 2, 3]);
    expect(await reopened.pendingFor('owner'), isEmpty);
    expect(await (await reopened.photoFile('stable-report')).exists(), false);
  });

  test('report without a photo also survives reopening and is sent once',
      () async {
    delivery.beforeReport = (_) async => throw noConnection();
    await submit(service());
    delivery.beforeReport = null;
    final reopened = service();
    await reopened.processPending();
    await reopened.processPending();
    expect(delivery.reports, hasLength(1));
    expect(delivery.photoCalls, 0);
    expect(await reopened.pendingFor('owner'), isEmpty);
  });

  test('failed photo retains both data and photo after report is confirmed',
      () async {
    delivery.beforePhoto = (_) async => throw noConnection();
    final result = await submit(service(), image: await photo());
    expect(result.state, ReportSendState.queued);
    expect(result.reportConfirmed, true);
    final reopened = service();
    final pending = (await reopened.pendingFor('owner')).single;
    expect(pending.reportConfirmed, true);
    expect(await (await reopened.photoFile(pending.id)).exists(), true);
    delivery.reports[pending.id]!['title'] = 'Edited after approval';
    delivery.beforePhoto = null;
    await reopened.processPending();
    expect(delivery.reportCalls, 1);
    expect(delivery.reports[pending.id]!['title'], 'Edited after approval');
    expect(delivery.photos, hasLength(1));
  });

  test('lost report acknowledgement retries the same ID after reopening',
      () async {
    delivery.beforeReport = (item) async {
      delivery.reports[item.id] = Map.of(item.fields);
      throw noConnection();
    };
    await submit(service(), image: await photo());
    delivery.beforeReport = null;
    await service().processPending();
    expect(delivery.reports.keys, ['stable-report']);
    expect(delivery.photos, hasLength(1));
  });

  test('simultaneous submit and background retries share one active delivery',
      () async {
    final queue = service();
    final entered = Completer<void>();
    final ack = Completer<void>();
    delivery.beforeReport = (_) async {
      entered.complete();
      await ack.future;
    };
    final first = submit(queue);
    final second = submit(queue);
    expect(identical(first, second), true);
    await entered.future;
    final background = queue.processPending();
    ack.complete();
    await Future.wait([first, second, background]);
    expect(delivery.reportCalls, 1);
    expect(delivery.reports, hasLength(1));
  });

  test('slow connection returns local confirmation and completes later once',
      () async {
    final queue = service(wait: const Duration(milliseconds: 30));
    final ack = Completer<void>();
    delivery.beforeReport = (_) => ack.future;
    final result = await submit(queue, image: await photo());
    expect(result.state, ReportSendState.queued);
    expect(await queue.pendingFor('owner'), hasLength(1));
    final background = queue.processPending();
    ack.complete();
    await background;
    expect(delivery.reportCalls, 1);
    expect(delivery.photoCalls, 1);
    expect(await queue.pendingFor('owner'), isEmpty);
  });

  test(
      'another account cannot send or see the original account pending entries',
      () async {
    delivery.beforeReport = (_) async => throw noConnection();
    await submit(service(), image: await photo());
    final calls = delivery.reportCalls;
    user = 'other';
    delivery.beforeReport = null;
    final reopened = service();
    expect(await reopened.pendingFor('other'), isEmpty);
    await reopened.processPending();
    expect(delivery.reportCalls, calls);
    expect(delivery.photos, isEmpty);
    user = 'owner';
    await reopened.processPending();
    expect(delivery.photos, hasLength(1));
  });

  test('signed out users leave pending reports untouched', () async {
    delivery.beforeReport = (_) async => throw noConnection();
    await submit(service());
    user = null;
    delivery.beforeReport = null;
    await service().processPending();
    expect(delivery.reports, isEmpty);
    expect(await service().pendingFor('owner'), hasLength(1));
  });

  test(
      'account change during report upload does not send the photo as someone else',
      () async {
    delivery.beforeReport = (_) async {
      user = 'other';
    };
    final result = await submit(service(), image: await photo());
    expect(result.state, ReportSendState.queued);
    expect(delivery.photoCalls, 0);
    expect((await service().pendingFor('owner')).single.reportConfirmed, true);
  });

  test('different simultaneous reports cannot overwrite each other locally',
      () async {
    delivery.beforeReport = (_) async => throw noConnection();
    final queue = service();
    await Future.wait(
        [submit(queue, id: 'first'), submit(queue, id: 'second')]);
    expect((await queue.pendingFor('owner')).map((e) => e.id),
        unorderedEquals(['first', 'second']));
    delivery.beforeReport = null;
    await service().processPending();
    expect(delivery.reports, hasLength(2));
  });

  test(
      'permission rejection retains the local photo and pauses automatic retries',
      () async {
    delivery.beforePhoto = (_) async => throw FirebaseException(
        plugin: 'firebase_storage', code: 'unauthorized');
    final queue = service();
    expect((await submit(queue, image: await photo())).state,
        ReportSendState.blocked);
    expect((await queue.pendingFor('owner')).single.blocked, true);
    await queue.processPending();
    expect(delivery.photoCalls, 1);
    delivery.beforePhoto = null;
    await queue.processPending(retryBlocked: true);
    expect(delivery.photoCalls, 2);
    expect(await queue.pendingFor('owner'), isEmpty);
  });

  test(
      'missing selected file does not send a report without its promised photo',
      () async {
    final image = await photo();
    await File(image.file.path!).delete();
    final queue = service();
    await expectLater(
        submit(queue, image: image), throwsA(isA<FileSystemException>()));
    expect(delivery.reportCalls, 0);
    expect(await queue.pendingFor('owner'), isEmpty);
  });

  test('bytes-only photos are copied and protected too', () async {
    delivery.beforeReport = (_) async => throw noConnection();
    final queue = service();
    await submit(queue,
        image: SelectedUpload(PlatformFile(
            name: 'memory.jpg',
            size: 3,
            bytes: Uint8List.fromList([4, 5, 6]))));
    expect(await (await queue.photoFile('stable-report')).readAsBytes(),
        [4, 5, 6]);
  });
  test('offline WEBP report survives restart and uses one stable photo path',
      () async {
    delivery.beforeReport = (_) async => throw noConnection();
    final queue = service();
    final image = SelectedUpload(PlatformFile(
        name: 'report.WEBP', size: 3, bytes: Uint8List.fromList([1, 2, 3])));
    expect((await submit(queue, image: image)).state, ReportSendState.queued);
    final recovered = service();
    expect(
        (await recovered.pendingFor('owner')).single.photoName, 'report.WEBP');
    delivery.beforeReport = null;
    await recovered.processPending();
    await recovered.processPending();
    expect(delivery.photos.keys,
        ['reports/stable-report/photos/stable-report_photo.webp']);
    expect(delivery.reports, hasLength(1));
    expect(await recovered.pendingFor('owner'), isEmpty);
  });

  test('oversized image fails before publishing the outbox or sending anything',
      () async {
    final queue = service();
    final bytes = Uint8List(FileService.maxImageBytes + 1);
    await expectLater(
        submit(queue,
            image: SelectedUpload(PlatformFile(
                name: 'large.png', size: bytes.length, bytes: bytes))),
        throwsA(isA<FileUploadException>()));
    expect(delivery.reportCalls, 0);
    expect(await queue.pendingFor('owner'), isEmpty);
  });

  test(
      'disk write failure leaves the form retryable and does not send anything',
      () async {
    await File(outbox.path).writeAsString('not a directory');
    await expectLater(submit(service()), throwsA(isA<FileSystemException>()));
    expect(delivery.reportCalls, 0);
  });

  test('a changed account cannot persist a new submission', () async {
    user = 'other';
    final queue = service();
    await expectLater(submit(queue), throwsA(isA<StateError>()));
    expect(delivery.reportCalls, 0);
    expect(await queue.pendingFor('owner'), isEmpty);
    // The failed future must not remain stuck in the in-flight registry.
    user = 'owner';
    expect((await submit(queue)).state, ReportSendState.sent);
  });

  test('a pending ID cannot be reused to replace its original content',
      () async {
    delivery.beforeReport = (_) async => throw noConnection();
    final queue = service();
    await submit(queue);
    await expectLater(
        queue.submit(
            id: 'stable-report',
            expectedUserId: 'owner',
            fields: {...reportFields, 'title': 'Different'}),
        throwsA(isA<StateError>()));
    expect((await queue.pendingFor('owner')).single.fields, reportFields);
  });

  test('unsafe local identifiers are rejected before file operations',
      () async {
    await expectLater(
        submit(service(), id: '../escape'), throwsA(isA<FormatException>()));
    expect(delivery.reportCalls, 0);
  });

  test('returning to the app retries a durable pending report automatically',
      () async {
    delivery.beforeReport = (_) async => throw noConnection();
    await submit(service(), image: await photo());
    delivery.beforeReport = null;
    final reopened = service();
    final delivered = Completer<void>();
    final subscription = reopened.watch('owner').listen((items) {
      if (items.isEmpty &&
          delivery.photos.isNotEmpty &&
          !delivered.isCompleted) {
        delivered.complete();
      }
    });
    reopened.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await delivered.future.timeout(const Duration(seconds: 3));
    await subscription.cancel();
    expect(delivery.reports, hasLength(1));
    expect(delivery.photos, hasLength(1));
  });

  test(
      'a missing copied file is retained as a blocked entry rather than silently removed',
      () async {
    delivery.beforeReport = (_) async => throw noConnection();
    final queue = service();
    await submit(queue, image: await photo());
    await (await queue.photoFile('stable-report')).delete();
    delivery.beforeReport = null;
    await queue.processPending();
    expect((await queue.pendingFor('owner')).single.blocked, true);
    expect(delivery.photos, isEmpty);
  });

  test(
      'quota errors are blocked and never presented as a connection-only retry',
      () async {
    delivery.beforeReport = (_) async => throw FirebaseException(
        plugin: 'cloud_firestore', code: 'resource-exhausted');
    final queue = service();
    expect((await submit(queue)).state, ReportSendState.blocked);
    expect((await queue.pendingFor('owner')).single.blocked, true);
  });
}
