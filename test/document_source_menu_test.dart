import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/services/access_request_document_picker.dart';
import 'package:micomunidad/services/file_service.dart';
import 'package:micomunidad/widgets/document_source_menu.dart';
import 'package:micomunidad/widgets/upload_error_notice.dart';

void main() {
  for (final option in [
    (AccessDocumentSource.camera, 'Tomar foto', 'foto.jpg', [255, 216, 255]),
    (
      AccessDocumentSource.gallery,
      'Elegir de galería',
      'foto.png',
      [137, 80, 78, 71, 13, 10, 26, 10]
    ),
    (
      AccessDocumentSource.file,
      'Seleccionar archivo',
      'acta.pdf',
      [37, 80, 68, 70, 45]
    ),
  ]) {
    testWidgets(
        '${option.$2} uses document validation and returns selected file',
        (tester) async {
      SelectedUpload? result;
      AccessDocumentSource? source;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                        onPressed: () async {
                          result = await pickDocumentWithMenu(context,
                              pick: (value) async {
                            source = value;
                            return SelectedUpload(PlatformFile(
                                name: option.$3,
                                size: option.$4.length,
                                bytes: Uint8List.fromList(option.$4)));
                          });
                        },
                        child: const Text('Adjuntar documento'),
                      )))));
      await tester.tap(find.text('Adjuntar documento'));
      await tester.pumpAndSettle();
      for (final label in [
        'Tomar foto',
        'Elegir de galería',
        'Seleccionar archivo'
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text(option.$2));
      await tester.pumpAndSettle();
      expect(source, option.$1);
      expect(result?.name, option.$3);
    });
  }

  for (final oversized in [false, true]) {
    testWidgets(
        'rejects ${oversized ? 'over 5 MB' : 'incorrect extension'} from gallery',
        (tester) async {
      SelectedUpload? result;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                        onPressed: () async =>
                            result = await pickDocumentWithMenu(context,
                                pick: (_) async => SelectedUpload(PlatformFile(
                                      name: 'foto.jpg',
                                      size: oversized
                                          ? FileService.maxDocumentBytes + 1
                                          : 5,
                                      bytes: Uint8List.fromList(
                                          [37, 80, 68, 70, 45]),
                                    ))),
                        child: const Text('Añadir'),
                      )))));
      await tester.tap(find.text('Añadir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elegir de galería'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(
          find.text(oversized
              ? 'El archivo no puede superar 5 MB.'
              : 'La extensión del archivo no coincide con su formato real.'),
          findsOneWidget);
      dismissUploadError();
      await tester.pumpAndSettle();
    });
  }

  testWidgets('closing menu does not invoke a selector', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                      onPressed: () =>
                          pickDocumentWithMenu(context, pick: (_) async {
                        calls++;
                        return null;
                      }),
                      child: const Text('Añadir'),
                    )))));
    await tester.tap(find.text('Añadir'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('Tomar foto'))).pop();
    await tester.pumpAndSettle();
    expect(calls, 0);
  });
}
