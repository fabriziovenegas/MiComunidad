import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/services/file_service.dart';
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
    result = FilePickerResult([PlatformFile(name: name, size: size)]);
  }
}

void main() {
  late DemoFilePicker picker;
  setUp(() {
    picker = DemoFilePicker();
    FilePicker.platform = picker;
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
        expect(picker.extensions,
            image ? ['jpg', 'jpeg', 'png'] : ['jpg', 'jpeg', 'png', 'pdf']);
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
  });
}
