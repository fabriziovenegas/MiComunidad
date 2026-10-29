import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/services/file_service.dart';

void main() {
  final headers = <String, List<int>>{
    'jpg': [255, 216, 255, 224],
    'jpeg': [255, 216, 255, 225],
    'png': [137, 80, 78, 71, 13, 10, 26, 10],
    'webp': [82, 73, 70, 70, 0, 0, 0, 0, 87, 69, 66, 80],
    'pdf': [37, 80, 68, 70, 45, 49, 46, 55],
  };
  for (final name in headers.keys) {
    for (final actual in headers.keys) {
      test('$actual bytes with .$name name respect the actual format', () {
        void validate() => FileService.validateFileHeader(
            'fictional.${name.toUpperCase()}', headers[actual]!);
        final same = name == actual ||
            (['jpg', 'jpeg'].contains(name) &&
                ['jpg', 'jpeg'].contains(actual));
        if (same) {
          expect(validate, returnsNormally);
        } else {
          expect(validate, throwsA(isA<FileUploadException>()));
        }
      });
    }
  }
  test('HEIF, empty and truncated headers are not stored directly', () {
    for (final name in ['photo.heic', 'photo.heif', 'photo.gif', 'photo']) {
      expect(() => FileService.validateFileHeader(name, headers['jpg']!),
          throwsA(isA<FileUploadException>()));
    }
    for (final name in headers.keys) {
      expect(() => FileService.validateFileHeader('file.$name', []),
          throwsA(isA<FileUploadException>()));
      expect(() => FileService.validateFileHeader('file.$name', [1, 2, 3]),
          throwsA(isA<FileUploadException>()));
    }
  });
  test('bytes-only PDF and a JPG photograph of an acta remain valid', () async {
    for (final name in ['pdf', 'jpg']) {
      final bytes = Uint8List.fromList(headers[name]!);
      await FileService.validateSelectedFormat(SelectedUpload(
          PlatformFile(name: 'acta.$name', size: bytes.length, bytes: bytes)));
    }
  });
  test('file-backed validation rejects a renamed PDF and accepts its real name',
      () async {
    final directory = await Directory.systemTemp.createTemp('format-test-');
    addTearDown(() async {
      expect(await directory.resolveSymbolicLinks(), contains('format-test-'));
      await directory.delete(recursive: true);
    });
    final file = File('${directory.path}/fictional.pdf');
    await file.writeAsBytes(headers['pdf']!);
    await FileService.validateLocalFileFormat('fictional.pdf', file.path);
    await expectLater(
        FileService.validateLocalFileFormat('fictional.jpg', file.path),
        throwsA(isA<FileUploadException>()));
  });
  test('unreadable selections fail before any upload', () async {
    await expectLater(
        FileService.validateSelectedFormat(
            SelectedUpload(PlatformFile(name: 'photo.jpg', size: 10))),
        throwsA(isA<FileUploadException>()));
  });
}
