import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:micomunidad/services/attachment_delivery.dart';
import 'package:micomunidad/services/file_service.dart';
import 'package:micomunidad/services/heif_image_converter.dart';
import 'package:micomunidad/services/pending_upload_service.dart';
import 'package:micomunidad/services/pending_send.dart';
import 'package:micomunidad/services/photo_picker.dart';
import 'package:micomunidad/widgets/photo_source_menu.dart';
import 'access_request_document_picker_test.dart' show FakePhotoPicker;
import 'upload_picker_test.dart' show DemoFilePicker;

class MultiplePicker extends FakePhotoPicker {
  List<XFile> images = [];
  @override
  Future<List<XFile>> pickMultiImage(
      {double? maxWidth,
      double? maxHeight,
      int? imageQuality,
      int? limit,
      bool requestFullMetadata = true}) async {
    expect(requestFullMetadata, false);
    expect(imageQuality, isNull);
    return images;
  }
}

class BatchDelivery implements AttachmentDelivery {
  final calls = <String>[];
  Future<void> Function(PendingAttachment)? action;
  @override
  Future<void> deliver(PendingAttachment item) async {
    calls.add(item.id);
    await action?.call(item);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late MultiplePicker native;
  late DemoFilePicker files;
  late PhotoPicker picker;
  const jpeg = [255, 216, 255, 217];
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('micomunidad-multiple-photos-');
    native = MultiplePicker();
    files = DemoFilePicker();
    FilePicker.platform = files;
    picker = PhotoPicker(picker: native);
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HeifImageConverter.channel, null);
    final target = dir.absolute;
    expect(target.parent.path, Directory.systemTemp.absolute.path);
    expect(target.path, contains('micomunidad-multiple-photos-'));
    await target.delete(recursive: true);
  });
  Future<XFile> photo(String name, List<int> bytes) async {
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes);
    return XFile(f.path);
  }

  SelectedUpload selected(String name) => SelectedUpload(PlatformFile(
      name: name, size: jpeg.length, bytes: Uint8List.fromList(jpeg)));

  test(
      'gallery returns several photos, skipping duplicate paths and invalid files',
      () async {
    final first = await photo('first.jpg', jpeg);
    native.images = [
      first,
      await photo('second.png', [137, 80, 78, 71, 13, 10, 26, 10]),
      first,
      await photo('renamed.jpg', [37, 80, 68, 70, 45]),
      await photo('wrong.pdf', [37, 80, 68, 70, 45])
    ];
    final result = await picker.pick(PhotoSource.gallery);
    expect(result.photos.map((p) => p.name), ['first.jpg', 'second.png']);
    expect(result.errors.length, 2);
  });
  test('photo limit remains 10 MB, not the identity document 5 MB limit',
      () async {
    final valid = Uint8List(6 * 1024 * 1024)..setAll(0, jpeg);
    final oversized = Uint8List(FileService.maxImageBytes + 1)..setAll(0, jpeg);
    native.images = [
      await photo('valid.jpg', valid),
      await photo('large.jpg', oversized)
    ];
    final result = await picker.pick(PhotoSource.gallery);
    expect(result.photos.single.size, valid.length);
    expect(result.errors.single, contains('10 MB'));
  });
  test('HEIC/HEIF conversion stays local with the existing photo limit',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HeifImageConverter.channel, (call) async {
      expect(call.arguments['maxBytes'], FileService.maxImageBytes);
      return Uint8List.fromList(jpeg);
    });
    native.images = [
      await photo('a.heic', [0]),
      await photo('b.heif', [0])
    ];
    final result = await picker.pick(PhotoSource.gallery);
    expect(result.photos.map((p) => p.name), ['a.jpg', 'b.jpg']);
    expect(result.errors, isEmpty);
  });
  test('files selector supports multiple photos without accepting PDF',
      () async {
    files.result =
        FilePickerResult([selected('a.jpg').file, selected('b.jpeg').file]);
    final result = await picker.pick(PhotoSource.files);
    expect(result.photos.length, 2);
    expect(files.extensions, FileService.selectableImageExtensions);
    expect(files.extensions, isNot(contains('pdf')));
  });
  test(
      'camera and initial report use a single photo; cancellation and denied access are handled',
      () async {
    native.file = await photo('camera.jpg', jpeg);
    expect((await picker.pick(PhotoSource.camera)).photos.length, 1);
    expect(native.source, ImageSource.camera);
    expect(
        (await picker.pick(PhotoSource.gallery, multiple: false)).photos.length,
        1);
    expect(native.source, ImageSource.gallery);
    native.file = null;
    expect((await picker.pick(PhotoSource.camera)).photos, isEmpty);
    native.error = PlatformException(code: 'camera_access_denied');
    await expectLater(
        picker.pick(PhotoSource.camera), throwsA(isA<FileUploadException>()));
  });

  for (final collection in ['projects', 'reports', 'events']) {
    test(
        '$collection persists whole batch before network, offline survives restart and retries once',
        () async {
      var offline = true;
      final delivery = BatchDelivery();
      PendingUploadService service() => PendingUploadService(
          delivery: delivery,
          currentUserId: () => 'fictional-user',
          supportDirectory: () async => dir,
          projectId: () => 'demo-photos',
          isOffline: () async => offline);
      final first = service();
      final result = await first.sendPhotos(
          collection: collection,
          documentId: 'fictional-content',
          photos: [selected('a.jpg'), selected('b.jpg'), selected('c.jpg')]);
      expect(result.results.every((r) => r.state == PendingSendState.queued),
          true);
      expect(delivery.calls, isEmpty);
      expect((await first.pendingFor('fictional-user')).length, 3);
      final resumed = service();
      delivery.action = (_) async {
        expect((await resumed.pendingFor('fictional-user')).isNotEmpty, true);
      };
      offline = false;
      await resumed.processPending();
      await resumed.processPending();
      expect(delivery.calls.length, 3);
      expect(delivery.calls.toSet().length, 3);
      expect(await resumed.pendingFor('fictional-user'), isEmpty);
    });
  }
  test(
      'slow connected batch is fully persisted before the first upload completes',
      () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final delivery = BatchDelivery();
    final service = PendingUploadService(
        delivery: delivery,
        currentUserId: () => 'fictional-user',
        supportDirectory: () async => dir,
        projectId: () => 'demo-photos',
        isOffline: () async => false,
        foregroundWait: const Duration(milliseconds: 10));
    delivery.action = (_) async {
      if (!started.isCompleted) {
        started.complete();
        await gate.future;
      }
    };
    final result = service.sendPhotos(
        collection: 'projects',
        documentId: 'fictional-content',
        photos: [selected('a.jpg'), selected('b.jpg'), selected('c.jpg')]);
    await started.future;
    expect((await service.pendingFor('fictional-user')).length, 3);
    expect(delivery.calls.length, 1);
    gate.complete();
    expect(
        (await result).results.every((r) => r.state == PendingSendState.sent),
        true);
    expect(delivery.calls.toSet().length, 3);
  });
  test('changing accounts while selecting cannot upload as a different member',
      () async {
    final delivery = BatchDelivery();
    final service = PendingUploadService(
        delivery: delivery,
        currentUserId: () => 'other-fictional-user',
        supportDirectory: () async => dir,
        projectId: () => 'demo-photos',
        isOffline: () async => false);
    await expectLater(
        service.sendPhotos(
            collection: 'projects',
            documentId: 'fictional-content',
            photos: [selected('a.jpg')],
            expectedUserId: 'fictional-user'),
        throwsStateError);
    expect(delivery.calls, isEmpty);
    expect(await service.pendingFor('other-fictional-user'), isEmpty);
  });
  test('a blocked photo does not stop other photos or duplicate completed ones',
      () async {
    final delivery = BatchDelivery();
    var blocked = true;
    delivery.action = (item) async {
      if (blocked && item.name == 'b.jpg') {
        throw FirebaseException(
            plugin: 'firebase_storage', code: 'unauthorized');
      }
    };
    final service = PendingUploadService(
        delivery: delivery,
        currentUserId: () => 'fictional-user',
        supportDirectory: () async => dir,
        projectId: () => 'demo-photos',
        isOffline: () async => false);
    final result = await service.sendPhotos(
        collection: 'projects',
        documentId: 'fictional-content',
        photos: [selected('a.jpg'), selected('b.jpg'), selected('c.jpg')]);
    expect(result.results.map((r) => r.state), [
      PendingSendState.sent,
      PendingSendState.blocked,
      PendingSendState.sent
    ]);
    expect((await service.pendingFor('fictional-user')).single.name, 'b.jpg');
    blocked = false;
    await service.processPending(retryBlocked: true);
    expect(delivery.calls.length, 4);
    expect(delivery.calls[0], isNot(delivery.calls.last));
    expect(await service.pendingFor('fictional-user'), isEmpty);
  });
  test(
      'invalid local file cannot be queued; valid peers still send; unauthenticated batch denied',
      () async {
    final delivery = BatchDelivery();
    String? user = 'fictional-user';
    final service = PendingUploadService(
        delivery: delivery,
        currentUserId: () => user,
        supportDirectory: () async => dir,
        projectId: () => 'demo-photos',
        isOffline: () async => false);
    final result = await service.sendPhotos(
        collection: 'events',
        documentId: 'fictional-content',
        photos: [
          selected('a.jpg'),
          SelectedUpload(PlatformFile(
              name: 'fake.jpg',
              size: 5,
              bytes: Uint8List.fromList([37, 80, 68, 70, 45])))
        ]);
    expect(result.results.single.state, PendingSendState.sent);
    expect(result.failures.length, 1);
    expect(delivery.calls.length, 1);
    user = null;
    await expectLater(
        service.sendPhotos(
            collection: 'events',
            documentId: 'fictional-content',
            photos: [selected('a.jpg')]),
        throwsA(isA<FileUploadException>()));
  });
  testWidgets('menu routes the three sources and cancellation never picks',
      (tester) async {
    final choices = <PhotoSource>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => pickPhotosWithMenu(context,
                            pick: (source, multiple) async {
                          expect(multiple, true);
                          choices.add(source);
                          return const PhotoSelection([]);
                        }),
                    child: const Text('Añadir fotografía'))))));
    for (final label in [
      'Tomar foto',
      'Elegir de galería',
      'Seleccionar archivos'
    ]) {
      await tester.tap(find.text('Añadir fotografía'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    expect(
        choices, [PhotoSource.camera, PhotoSource.gallery, PhotoSource.files]);
    await tester.tap(find.text('Añadir fotografía'));
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(choices.length, 3);
  });
}
