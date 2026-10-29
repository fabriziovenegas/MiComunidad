// Fictional local files only. No Firebase initialization or network calls.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/services/file_service.dart';
import 'package:micomunidad/services/local_attachment_preview.dart';
import 'package:micomunidad/screens/auth/signup_screen.dart';
import 'package:micomunidad/widgets/access_request_documents_section.dart';
import 'package:micomunidad/widgets/selected_upload_preview.dart';
import 'package:micomunidad/widgets/upload_error_notice.dart';

final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a0VkAAAAASUVORK5CYII=');
final pdf =
    Uint8List.fromList(utf8.encode('%PDF-1.4\nFictional local preview'));
SelectedUpload selected(String name, Uint8List bytes, {int? size}) =>
    SelectedUpload(
        PlatformFile(name: name, size: size ?? bytes.length, bytes: bytes));

Future<void> section(WidgetTester tester, List<SelectedUpload> initial,
    {bool enabled = true}) async {
  var files = initial;
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: StatefulBuilder(
    builder: (context, update) => ListView(children: [
      AccessRequestDocumentsSection(
          documents: files,
          enabled: enabled,
          pick: (_) async => null,
          onChanged: (next) => update(() => files = next)),
    ]),
  ))));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;
  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LocalAttachmentPreview.channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() {
    dismissUploadError();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LocalAttachmentPreview.channel, null);
  });

  test(
      'memory preview preserves original image/PDF bytes and needs no signed-in account',
      () async {
    for (final file in [
      selected('photo.png', png),
      selected('minutes.pdf', pdf)
    ]) {
      final before = Uint8List.fromList(file.file.bytes!);
      expect(await LocalAttachmentPreview.read(file), before);
      expect(file.file.bytes, before);
    }
    expect(calls, isEmpty);
  });

  test(
      'local path preview is read-only and uses the real current header and size',
      () async {
    final dir = await Directory.systemTemp.createTemp('micomunidad-preview-');
    try {
      final file = File('${dir.path}${Platform.pathSeparator}photo.png');
      await file.writeAsBytes(png);
      final selection = SelectedUpload(
          PlatformFile(name: 'photo.png', size: png.length, path: file.path));
      expect(await LocalAttachmentPreview.read(selection), png);
      expect(await file.readAsBytes(), png);
      await file.writeAsBytes(pdf);
      await expectLater(LocalAttachmentPreview.read(selection),
          throwsA(isA<FileUploadException>()));
      await file.writeAsBytes(Uint8List(FileService.maxDocumentBytes + 1));
      await expectLater(LocalAttachmentPreview.read(selection),
          throwsA(isA<FileUploadException>()));
      await file.delete();
      await expectLater(
          LocalAttachmentPreview.read(selection),
          throwsA(isA<FileUploadException>().having((e) => e.message,
              'friendly message', isNot(contains(dir.path)))));
    } finally {
      expect(
          dir.absolute.path,
          startsWith(
              '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}micomunidad-preview-'));
      await dir.delete(recursive: true);
    }
  });

  test(
      'oversized bytes, mismatched types and missing source cannot reach the native viewer',
      () async {
    final noSource =
        SelectedUpload(PlatformFile(name: 'missing.pdf', size: 100));
    for (final file in [
      selected('wrong.pdf', png),
      selected('large.pdf', Uint8List(FileService.maxDocumentBytes + 1),
          size: 1),
      noSource
    ]) {
      await expectLater(LocalAttachmentPreview.openPdf(file),
          throwsA(isA<FileUploadException>()));
    }
    expect(calls, isEmpty);
  });

  test('PDF opens a temporary local copy through the existing viewer channel',
      () async {
    final file = selected('receipt.pdf', pdf);
    await LocalAttachmentPreview.openPdf(file);
    expect(calls.length, 1);
    expect(calls.single.method, 'openDocument');
    expect(calls.single.arguments,
        {'bytes': pdf, 'contentType': 'application/pdf'});
    expect(file.file.bytes, pdf);
  });

  testWidgets(
      'photo opens with zoom and returning preserves every selected file',
      (tester) async {
    final first = selected('photo.png', png),
        second = selected('receipt.pdf', pdf);
    await section(tester, [first, second]);
    await tester.tap(find.byKey(const ValueKey('preview-document-0')));
    await tester.pumpAndSettle();
    expect(find.byType(SelectedImagePreview), findsOneWidget);
    expect(
        find.byKey(const ValueKey('selected-image-preview')), findsOneWidget);
    expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .maxScale,
        5);
    expect(calls, isEmpty);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('2 de 3'), findsOneWidget);
    expect(find.text('photo.png'), findsOneWidget);
    expect(find.text('receipt.pdf'), findsOneWidget);
    expect(first.file.bytes, png);
    expect(second.file.bytes, pdf);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'PDF opening keeps the form in place, preserves selection and handles double taps',
      (tester) async {
    final waiting = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LocalAttachmentPreview.channel, (call) {
      calls.add(call);
      return waiting.future;
    });
    await section(
        tester, [selected('receipt.pdf', pdf), selected('photo.png', png)]);
    final row = find.byKey(const ValueKey('preview-document-0'));
    await tester.tap(row);
    await tester.pump();
    await tester.tap(row);
    await tester.pump();
    expect(calls.length, 1);
    waiting.complete();
    await tester.pumpAndSettle();
    expect(find.text('2 de 3'), findsOneWidget);
    expect(find.byType(SelectedImagePreview), findsNothing);
    expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('remove-document-0')))
            .onPressed,
        isNotNull);
  });

  testWidgets(
      'removing a file never opens it and preview respects sending state',
      (tester) async {
    await section(
        tester, [selected('receipt.pdf', pdf), selected('photo.png', png)]);
    await tester.tap(find.byKey(const ValueKey('remove-document-0')));
    await tester.pumpAndSettle();
    expect(find.text('1 de 3'), findsOneWidget);
    expect(find.text('receipt.pdf'), findsNothing);
    expect(calls, isEmpty);
    await section(tester, [selected('receipt.pdf', pdf)], enabled: false);
    expect(
        tester
            .widget<InkWell>(find.byKey(const ValueKey('preview-document-0')))
            .onTap,
        isNull);
    expect(calls, isEmpty);
  });

  for (final code in ['no-viewer', 'open-failed']) {
    testWidgets(
        'native PDF error $code shows a readable notice without losing the selection',
        (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              LocalAttachmentPreview.channel,
              (_) async => throw PlatformException(
                  code: code, message: 'internal path'));
      await section(tester, [selected('receipt.pdf', pdf)]);
      await tester.tap(find.byKey(const ValueKey('preview-document-0')));
      await tester.pumpAndSettle();
      expect(find.text('1 de 3'), findsOneWidget);
      expect(find.text('receipt.pdf'), findsOneWidget);
      expect(find.byKey(const ValueKey('upload-error-notice')), findsOneWidget);
      expect(find.textContaining('internal path'), findsNothing);
      expect(
          find.text(code == 'no-viewer'
              ? 'No hay una aplicación instalada para abrir archivos PDF.'
              : 'No se pudo abrir el PDF. Inténtalo nuevamente.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'unreadable image shows an error and can return to the selected list',
      (tester) async {
    await section(tester, [selected('broken.png', pdf)]);
    await tester.tap(find.byKey(const ValueKey('preview-document-0')));
    await tester.pumpAndSettle();
    expect(
        find.text('La extensión del archivo no coincide con su formato real.'),
        findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('1 de 3'), findsOneWidget);
    expect(find.text('broken.png'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'full signup retains all entered fields and both attachments after image/PDF preview',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(414, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final files = [selected('photo.png', png), selected('receipt.pdf', pdf)];
    var next = 0, submissions = 0;
    await tester.pumpWidget(MaterialApp(
        home: SignupScreen(
            pickDocument: (_) async => files[next++],
            submitRequest: (
                {required name,
                required dni,
                required phone,
                required email,
                required address,
                required timeLivingHere,
                required reason,
                required identityDocuments}) async {
              submissions++;
              return 'never-submit-for-preview';
            })));
    final fields = find.byType(TextFormField);
    const values = [
      'Fictional Applicant',
      '00000001',
      '000000001',
      'applicant@example.com',
      'Fictional address',
      'Fictional reason'
    ];
    for (var i = 0; i < values.length; i++) {
      await tester.ensureVisible(fields.at(i));
      await tester.enterText(fields.at(i), values[i]);
    }
    final time = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(time);
    await tester.tap(time);
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 a 5 años').last);
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.ensureVisible(find.text('Añadir archivo'));
      await tester.tap(find.text('Añadir archivo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Seleccionar archivo'));
      await tester.pumpAndSettle();
    }
    final first = find.byKey(const ValueKey('preview-document-0'));
    await tester.ensureVisible(first);
    await tester.tap(first);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    final second = find.byKey(const ValueKey('preview-document-1'));
    await tester.ensureVisible(second);
    await tester.tap(second);
    await tester.pumpAndSettle();
    expect(calls.length, 1);
    expect(submissions, 0);
    expect(find.text('2 de 3'), findsOneWidget);
    for (var i = 0; i < values.length; i++) {
      expect(tester.widget<TextFormField>(fields.at(i)).controller!.text,
          values[i]);
    }
    expect(find.text('1 a 5 años'), findsOneWidget);
    expect(files[0].file.bytes, png);
    expect(files[1].file.bytes, pdf);
    expect(tester.takeException(), isNull);
  });
}
