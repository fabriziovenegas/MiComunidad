// Fault injection only: no cloud resources or real data are touched.
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:micomunidad/services/attachment_delivery.dart';
import 'package:micomunidad/services/file_service.dart';
import 'package:micomunidad/services/heif_image_converter.dart';
import 'package:micomunidad/services/pending_upload_service.dart';
import 'pending_upload_service_test.dart' show UploadDatabase;
import 'report_delivery_test.dart'
    show DeliveryStorage, fakeAttachmentRegistration;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final collection in ['projects', 'reports', 'events']) {
    for (final kind in ['photos', if (collection != 'reports') 'minutes']) {
      for (final extension in [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'heic',
        'heif',
        if (kind == 'minutes') 'pdf'
      ]) {
        test(
            '$collection/$kind/$extension survives offline, missing source and restart, then sends once',
            () async {
          SharedPreferences.setMockInitialValues({});
          final temporary = await Directory.systemTemp
              .createTemp('offline-attachment-matrix-');
          try {
            final bytes = switch (extension) {
              'jpg' || 'jpeg' => [255, 216, 255, 224],
              'pdf' => [37, 80, 68, 70, 45],
              'webp' => [82, 73, 70, 70, 0, 0, 0, 0, 87, 69, 66, 80],
              'heic' || 'heif' => [
                  0,
                  0,
                  0,
                  24,
                  102,
                  116,
                  121,
                  112,
                  104,
                  101,
                  105,
                  99
                ],
              _ => [137, 80, 78, 71, 13, 10, 26, 10],
            };
            final source = File('${temporary.path}/source.$extension');
            await source.writeAsBytes(bytes);
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(HeifImageConverter.channel,
                    (_) async => Uint8List.fromList([255, 216, 255, 224, 255, 217]));
            final selected = await (kind == 'photos'
                    ? FileService.preparePhoto
                    : FileService.prepareIdentityDocument)(
                PlatformFile(
                    name: 'source.$extension',
                    size: bytes.length,
                    path: source.path));
            var offline = true;
            final db = UploadDatabase();
            final storage = DeliveryStorage();
            final delivery = FirebaseAttachmentDelivery(
                firestore: db,
                storage: storage,
                currentUserId: () => 'owner',
                refreshAuth: () async {},
                registerAttachment: fakeAttachmentRegistration(db, storage));
            PendingUploadService service() => PendingUploadService(
                delivery: delivery,
                currentUserId: () => 'owner',
                projectId: () => 'demo-offline-matrix',
                isOffline: () async => offline,
                supportDirectory: () async => temporary);
            final first = service();
            final result = await first.send(
                collection: collection,
                documentId: 'demo-project',
                kind: kind,
                selected: selected);
            expect(result.state.name, 'queued');
            expect(storage.writes, isEmpty);
            expect(db.writes, isEmpty);
            final saved = (await first.pendingFor('owner')).single;
            final expectedBytes = await File(saved.localPath).readAsBytes();
            expect(expectedBytes, isNotEmpty);
            if (extension == 'heic' || extension == 'heif') {
              expect(saved.name.endsWith('.jpg'), true);
            }
            await source.delete(); // Android picker cache is no longer needed.
            final reopened = service();
            expect((await reopened.pendingFor('owner')).single.id, saved.id);
            expect(await File(saved.localPath).readAsBytes(), expectedBytes);
            await reopened
                .processPending(); // Still offline: never mark as sent.
            expect(storage.writes, isEmpty);
            offline = false;
            await reopened.processPending();
            await reopened.processPending();
            expect(storage.writes, [saved.storagePath]);
            expect(db.writes, [saved.metadataPath]);
            expect(storage.contentTypes[saved.storagePath],
                FileService.contentTypeForName(saved.name));
            expect(await reopened.pendingFor('owner'), isEmpty);
            expect(await File(saved.localPath).exists(), false);
          } finally {
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(HeifImageConverter.channel, null);
            await temporary.delete(recursive: true);
          }
        });
      }
    }
  }
}
