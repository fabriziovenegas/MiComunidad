import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/services/file_service.dart';
import 'package:micomunidad/services/heif_image_converter.dart';
import 'package:micomunidad/widgets/upload_picker.dart';
import 'package:micomunidad/screens/auth/signup_screen.dart';

class DemoFilePicker extends FilePicker {
  FilePickerResult? result;
  Object? error;
  List<String>? extensions;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    extensions = allowedExtensions;
    if (error != null) throw error!;
    return result;
  }

  void select(int size, {String name = 'demo.jpg'}) {
    final header = switch (FileService.extensionOf(name)) {
      'png' => [137, 80, 78, 71, 13, 10, 26, 10],
      'webp' => [82, 73, 70, 70, 0, 0, 0, 0, 87, 69, 66, 80],
      'pdf' => [37, 80, 68, 70, 45],
      _ => [0xff, 0xd8, 0xff, 0xd9],
    };
    result = FilePickerResult([
      PlatformFile(name: name, size: size, bytes: Uint8List.fromList(header))
    ]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DemoFilePicker picker;
  setUp(() {
    picker = DemoFilePicker();
    FilePicker.platform = picker;
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HeifImageConverter.channel, null);
  });

  for (final extension in ['heic', 'HEIC', 'heif', 'HEIF']) {
    for (final document in [false, true]) {
      test(
          '$extension is converted to JPEG in the ${document ? 'document' : 'photo'} picker',
          () async {
        final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 1, 2, 0xff, 0xd9]);
        MethodCall? received;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(HeifImageConverter.channel, (call) async {
          received = call;
          return jpeg;
        });
        picker.result = FilePickerResult([
          PlatformFile(
              name: 'foto.original.$extension',
              size: 100,
              path: '/photo/source')
        ]);
        final selected = await (document
            ? FileService.pickIdentityDocument()
            : FileService.pickImage());
        expect(selected!.name, 'foto.original.jpg');
        expect(selected.size, jpeg.length);
        expect(selected.file.bytes, jpeg);
        expect(selected.file.path, isNull);
        expect(FileService.contentTypeForName(selected.name), 'image/jpeg');
        expect(received!.method, 'heifToJpeg');
        expect(received!.arguments['path'], '/photo/source');
        expect(
            received!.arguments['maxBytes'],
            document
                ? FileService.maxDocumentBytes
                : FileService.maxImageBytes);
        // Only accepted output formats can enter the upload/outbox layer.
        expect(FileService.imageExtensions,
            isNot(contains(extension.toLowerCase())));
      });
    }
  }

  for (final document in [false, true]) {
    final pick =
        document ? FileService.pickIdentityDocument : FileService.pickImage;
    final limit =
        document ? FileService.maxDocumentBytes : FileService.maxImageBytes;
    test(
        'oversized HEIF source is rejected before conversion (document: $document)',
        () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(HeifImageConverter.channel, (_) async {
        calls++;
        return null;
      });
      picker.select(limit + 1, name: 'large.heif');
      await expectLater(pick(), throwsA(isA<FileUploadException>()));
      expect(calls, 0);
    });
    test('oversized converted JPEG is rejected (document: $document)',
        () async {
      final jpeg = Uint8List(limit + 1);
      jpeg[0] = 0xff;
      jpeg[1] = 0xd8;
      jpeg[jpeg.length - 2] = 0xff;
      jpeg[jpeg.length - 1] = 0xd9;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              HeifImageConverter.channel, (_) async => jpeg);
      picker.select(100, name: 'large.heic');
      await expectLater(pick(), throwsA(isA<FileUploadException>()));
    });
  }

  for (final code in ['unsupported_device', 'conversion_failed', 'too_large']) {
    test('conversion failure $code becomes a friendly picker error', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(HeifImageConverter.channel, (_) async {
        throw PlatformException(code: code, message: 'internal native detail');
      });
      picker.select(100, name: 'photo.heif');
      await expectLater(
          FileService.pickImage(),
          throwsA(isA<FileUploadException>().having((error) => error.message,
              'message', isNot(contains('internal')))));
    });
  }

  test('invalid conversion output never enters an upload queue', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HeifImageConverter.channel,
            (_) async => Uint8List.fromList([1, 2, 3]));
    picker.select(100, name: 'photo.heic');
    await expectLater(
        FileService.pickImage(), throwsA(isA<FileUploadException>()));
  });

  test('HEIF bytes-only selections are forwarded without needing a path',
      () async {
    final original = Uint8List.fromList([10, 20, 30]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HeifImageConverter.channel, (call) async {
      expect(call.arguments['bytes'], original);
      expect(call.arguments['path'], isNull);
      return Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]);
    });
    picker.result = FilePickerResult([
      PlatformFile(name: 'photo.heif', size: original.length, bytes: original)
    ]);
    expect((await FileService.pickImage())!.name, 'photo.jpg');
  });

  for (final extension in ['jpg', 'jpeg', 'png', 'webp', 'WEBP']) {
    test('photo picker accepts $extension', () async {
      picker.select(100, name: 'photo.$extension');
      expect((await FileService.pickImage())!.name, 'photo.$extension');
    });
    test('document picker accepts $extension', () async {
      picker.select(100, name: 'document.$extension');
      expect((await FileService.pickIdentityDocument())!.name,
          'document.$extension');
    });
  }
  for (final extension in ['gif', 'bmp', 'svg', 'txt']) {
    test('unconfirmed or unsupported $extension stays rejected', () async {
      picker.select(100, name: 'photo.$extension');
      await expectLater(
          FileService.pickImage(), throwsA(isA<FileUploadException>()));
      await expectLater(FileService.pickIdentityDocument(),
          throwsA(isA<FileUploadException>()));
    });
  }
  test('PDF remains a document and is never accepted as a photo', () async {
    picker.select(100, name: 'acta.pdf');
    await expectLater(
        FileService.pickImage(), throwsA(isA<FileUploadException>()));
    expect((await FileService.pickIdentityDocument())!.name, 'acta.pdf');
  });
  test('every supported extension gets its actual MIME type', () {
    for (final entry in {
      'photo.jpg': 'image/jpeg',
      'photo.JPEG': 'image/jpeg',
      'photo.PNG': 'image/png',
      'photo.webp': 'image/webp',
      'photo.WEBP': 'image/webp',
      'document.pdf': 'application/pdf'
    }.entries) {
      expect(FileService.contentTypeForName(entry.key), entry.value);
    }
    expect(() => FileService.contentTypeForName('photo.heic'),
        throwsA(isA<FileUploadException>()));
  });

  for (final image in [true, false]) {
    final pick =
        image ? FileService.pickImage : FileService.pickIdentityDocument;
    final limit =
        image ? FileService.maxImageBytes : FileService.maxDocumentBytes;
    final kind = image ? 'image' : 'document';
    final message = image
        ? 'La imagen no puede superar ${limit ~/ (1024 * 1024)} MB.'
        : 'El archivo no puede superar ${limit ~/ (1024 * 1024)} MB.';

    for (final size in [limit - 1, limit]) {
      test('$kind permits $size bytes without changing the limit', () async {
        picker.select(size);
        expect((await pick())?.size, size);
        expect(
            picker.extensions,
            image
                ? ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif']
                : ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'pdf']);
      });
    }

    testWidgets('$kind oversized selection shows its specific top error notice',
        (tester) async {
      picker.select(limit + 1);
      var accepted = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final selected = await pickUploadWithFeedback(context, pick);
            if (selected != null) accepted++;
          },
          child: const Text('Select'),
        ),
      ))));
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('upload-error-notice')),
              matching: find.text(message)),
          findsOneWidget);
      expect(accepted, 0);
      expect(tester.takeException(), isNull);

      // Retrying with a valid file proceeds normally after a rejected one.
      picker.select(limit);
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      expect(accepted, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$kind cancellation does not show an error or accept a file',
        (tester) async {
      SelectedUpload? selected;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              selected = await pickUploadWithFeedback(context, pick),
          child: const Text('Select'),
        ),
      ))));
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(find.byKey(const ValueKey('upload-error-notice')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unexpected picker errors show a friendly message',
      (tester) async {
    picker.error = StateError('internal demo detail');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
        onPressed: () => pickUploadWithFeedback(context, FileService.pickImage),
        child: const Text('Select'),
      ),
    ))));
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    expect(
        find.text('No se pudo seleccionar el archivo. Inténtalo nuevamente.'),
        findsOneWidget);
    expect(find.textContaining('internal demo detail'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Cerrar aviso'));
    await tester.pump();
  });

  testWidgets('a PDF renamed as JPG displays the existing top error notice',
      (tester) async {
    picker.result = FilePickerResult([
      PlatformFile(
          name: 'renamed.jpg',
          size: 5,
          bytes: Uint8List.fromList([37, 80, 68, 70, 45]))
    ]);
    SelectedUpload? accepted;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
        onPressed: () async => accepted =
            await pickUploadWithFeedback(context, FileService.pickImage),
        child: const Text('Select'),
      ),
    ))));
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    expect(
        find.text('La extensión del archivo no coincide con su formato real.'),
        findsOneWidget);
    expect(accepted, isNull);
  });

  for (final fail in [true, false]) {
    testWidgets('closing the view while picking is safe (error: $fail)',
        (tester) async {
      final pending = Completer<SelectedUpload?>();
      SelectedUpload? selected;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
        builder: (context) => TextButton(
          onPressed: () async => selected =
              await pickUploadWithFeedback(context, () => pending.future),
          child: const Text('Select'),
        ),
      ))));
      await tester.tap(find.text('Select'));
      await tester.pumpWidget(const SizedBox());
      if (fail) {
        pending
            .completeError(const FileUploadException('Demo selection error'));
      } else {
        pending
            .complete(SelectedUpload(PlatformFile(name: 'demo.jpg', size: 1)));
      }
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('signup shows 5 MB and preserves the previous valid attachment',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: SignupScreen()));
    picker.select(FileService.maxDocumentBytes, name: 'demo-document.pdf');
    await tester.ensureVisible(find.text('Toca para adjuntar tu documento'));
    await tester.tap(find.text('Toca para adjuntar tu documento'));
    await tester.pumpAndSettle();
    expect(find.text('demo-document.pdf'), findsOneWidget);

    picker.select(FileService.maxDocumentBytes + 1, name: 'too-large.pdf');
    await tester.tap(find.text('demo-document.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('El archivo no puede superar 5 MB.'), findsOneWidget);
    expect(find.text('demo-document.pdf'), findsOneWidget);
    expect(find.text('too-large.pdf'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Cerrar aviso'));
    await tester.pump();

    // A failed HEIF conversion must not discard the existing attachment.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HeifImageConverter.channel, (_) async {
      throw PlatformException(code: 'conversion_failed');
    });
    picker.select(100, name: 'broken.heic');
    await tester.tap(find.text('demo-document.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('demo-document.pdf'), findsOneWidget);
    expect(find.text('broken.heic'), findsNothing);
    expect(find.textContaining('No se pudo convertir la fotografía.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Cerrar aviso'));
    await tester.pump();
  });
}
