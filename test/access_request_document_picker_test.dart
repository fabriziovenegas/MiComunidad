import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:micomunidad/services/access_request_document_picker.dart';
import 'package:micomunidad/services/file_service.dart';
import 'package:micomunidad/services/heif_image_converter.dart';

class FakePhotoPicker extends ImagePicker {
  XFile? file;
  PlatformException? error;
  ImageSource? source;
  @override
  Future<XFile?> pickImage(
      {required ImageSource source,
      double? maxWidth,
      double? maxHeight,
      int? imageQuality,
      CameraDevice preferredCameraDevice = CameraDevice.rear,
      bool requestFullMetadata = true}) async {
    this.source = source;
    expect(imageQuality, isNull,
        reason: 'Do not silently compress or resize ordinary photos');
    expect(maxWidth, isNull);
    expect(maxHeight, isNull);
    expect(requestFullMetadata, isFalse);
    if (error != null) throw error!;
    return file;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late FakePhotoPicker native;
  late AccessRequestDocumentPicker picker;
  setUp(() async {
    directory =
        await Directory.systemTemp.createTemp('micomunidad-document-picker-');
    native = FakePhotoPicker();
    picker = AccessRequestDocumentPicker(picker: native);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HeifImageConverter.channel, null);
    await directory.delete(recursive: true);
  });
  Future<void> image(String name, List<int> bytes) async {
    final file = File('${directory.path}/$name');
    await file.writeAsBytes(bytes);
    native.file = XFile(file.path);
  }

  for (final source in [
    AccessDocumentSource.camera,
    AccessDocumentSource.gallery
  ]) {
    test(
        '$source uses the requested native image source and checks its real format',
        () async {
      await image('photo.jpg', [255, 216, 255, 217]);
      expect((await picker.pick(source))!.name, 'photo.jpg');
      expect(
          native.source,
          source == AccessDocumentSource.camera
              ? ImageSource.camera
              : ImageSource.gallery);
      await image('renamed.jpg', [37, 80, 68, 70, 45]);
      await expectLater(
          picker.pick(source), throwsA(isA<FileUploadException>()));
    });
  }
  test('camera or gallery cancellation returns no file', () async {
    expect(await picker.pick(AccessDocumentSource.camera), isNull);
    expect(await picker.pick(AccessDocumentSource.gallery), isNull);
  });
  test(
      'photos above 5 MB are rejected, even though other photo modules allow 10 MB',
      () async {
    final bytes = Uint8List(FileService.maxDocumentBytes + 1);
    bytes.setAll(0, [255, 216, 255]);
    await image('large.jpg', bytes);
    await expectLater(
        picker.pick(AccessDocumentSource.gallery),
        throwsA(isA<FileUploadException>().having(
            (e) => e.message, 'message', 'El archivo no puede superar 5 MB.')));
  });
  test(
      'HEIC and HEIF from the gallery keep the existing JPEG conversion and 5 MB check',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HeifImageConverter.channel, (call) async {
      expect(call.arguments['maxBytes'], FileService.maxDocumentBytes);
      return Uint8List.fromList([255, 216, 255, 217]);
    });
    for (final extension in ['heic', 'heif']) {
      await image('photo.$extension', [0, 0, 0, 24, 102, 116, 121, 112]);
      final file = (await picker.pick(AccessDocumentSource.gallery))!;
      expect(file.name, 'photo.jpg');
      expect(FileService.contentTypeForName(file.name), 'image/jpeg');
    }
  });
  test('unsupported gallery formats remain rejected and are never renamed',
      () async {
    await image('photo.gif', [71, 73, 70, 56, 57, 97]);
    await expectLater(picker.pick(AccessDocumentSource.gallery),
        throwsA(isA<FileUploadException>()));
  });
  for (final code in [
    'camera_access_denied',
    'photo_access_denied',
    'no_available_camera'
  ]) {
    test('$code returns a readable selection error', () async {
      native.error = PlatformException(code: code, message: 'internal details');
      await expectLater(
          picker.pick(AccessDocumentSource.camera),
          throwsA(isA<FileUploadException>().having(
              (e) => e.message, 'message', isNot(contains('internal')))));
    });
  }
}
