import 'dart:async';
import 'dart:typed_data';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/models/access_request.dart';
import 'package:micomunidad/services/access_request_document_picker.dart';
import 'package:micomunidad/services/access_request_documents_sender.dart';
import 'package:micomunidad/services/auth_service.dart';
import 'package:micomunidad/services/file_service.dart';
import 'package:micomunidad/screens/auth/signup_screen.dart';
import 'package:micomunidad/widgets/access_request_document_links.dart';
import 'package:micomunidad/widgets/access_request_documents_section.dart';
import 'package:micomunidad/widgets/upload_error_notice.dart';

SelectedUpload sample(String name, {int? size, List<int>? bytes}) {
  final content = Uint8List.fromList(bytes ??
      (name.endsWith('.pdf')
          ? [37, 80, 68, 70, 45, 49]
          : [255, 216, 255, 217]));
  return SelectedUpload(
      PlatformFile(name: name, size: size ?? content.length, bytes: content));
}

Future<void> mountSection(WidgetTester tester,
    {required Future<SelectedUpload?> Function(AccessDocumentSource) pick,
    List<SelectedUpload> initial = const [],
    bool enabled = true,
    double scale = 1,
    Future<List<SelectedUpload>> Function()? recover}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(414, 1100);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  var files = initial;
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: StatefulBuilder(
    builder: (context, update) => MediaQuery(
      data:
          MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: ListView(padding: const EdgeInsets.all(18), children: [
        AccessRequestDocumentsSection(
            documents: files,
            enabled: enabled,
            pick: pick,
            recover: recover,
            onChanged: (next) => update(() => files = next)),
      ]),
    ),
  ))));
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String label) async {
  final button = find.byKey(const ValueKey('add-access-document'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(dismissUploadError);
  for (final count in [1, 2, 3]) {
    test('all $count files upload before one submission with a single request',
        () async {
      final selected = [
        sample('receipt.pdf'),
        sample('photo.jpg'),
        sample('other.jpg')
      ].take(count).toList();
      final calls = <String>[];
      final result = await sendAccessRequestDocuments(
          documents: selected,
          upload: (f) async {
            calls.add(f.name);
            return UploadedFile(
                url: 'gs://demo/${f.name}', storagePath: 'demo/${f.name}');
          },
          submit: (files) async {
            expect(files.length, count);
            expect(calls.length, count);
            calls.add('submit');
            return 'request';
          });
      expect(result, 'request');
      expect(calls, [...selected.map((f) => f.name), 'submit']);
    });
  }
  test(
      'zero files, a fourth file, oversize and renamed PDF are stopped before uploading',
      () async {
    for (final files in <List<SelectedUpload>>[
      [],
      List.generate(4, (i) => sample('photo$i.jpg')),
      [sample('large.jpg', size: FileService.maxDocumentBytes + 1)],
      [
        sample('photo.jpg', bytes: [37, 80, 68, 70, 45])
      ],
    ]) {
      var uploads = 0, submissions = 0;
      await expectLater(
          sendAccessRequestDocuments(
              documents: files,
              upload: (_) async {
                uploads++;
                return const UploadedFile(url: '', storagePath: '');
              },
              submit: (_) async {
                submissions++;
              }),
          throwsA(isA<FileUploadException>()));
      expect(uploads, 0);
      expect(submissions, 0);
    }
  });
  test(
      'failure during second upload never calls submission and preserves the selected files',
      () async {
    final files = [
      sample('receipt.pdf'),
      sample('photo.jpg'),
      sample('other.jpg')
    ];
    var uploads = 0, submissions = 0;
    await expectLater(
        sendAccessRequestDocuments(
            documents: files,
            upload: (file) async {
              if (++uploads == 2) throw StateError('Fictional upload failure');
              return UploadedFile(
                  url: 'gs://demo/${file.name}', storagePath: file.name);
            },
            submit: (_) async {
              submissions++;
            }),
        throwsStateError);
    expect(uploads, 2);
    expect(submissions, 0);
    expect(files.length, 3);
  });

  testWidgets(
      'each of the three menu options adds one file, then a fourth is disabled',
      (tester) async {
    final sources = <AccessDocumentSource>[];
    await mountSection(tester, pick: (source) async {
      sources.add(source);
      return sample(
          'file${sources.length}.${source == AccessDocumentSource.file ? 'pdf' : 'jpg'}');
    });
    expect(find.text('0 de 3'), findsOneWidget);
    await choose(tester, 'Tomar foto');
    expect(find.text('1 de 3'), findsOneWidget);
    await choose(tester, 'Elegir de galería');
    expect(find.text('2 de 3'), findsOneWidget);
    await choose(tester, 'Seleccionar archivo');
    expect(find.text('3 de 3'), findsOneWidget);
    expect(sources, AccessDocumentSource.values);
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('add-access-document')))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const ValueKey('add-access-document')));
    await tester.pumpAndSettle();
    expect(find.text('Tomar foto'), findsNothing);
    expect(sources.length, 3);
    await tester.tap(find.byKey(const ValueKey('remove-document-1')));
    await tester.pumpAndSettle();
    expect(find.text('2 de 3'), findsOneWidget);
    expect(find.text('file2.jpg'), findsNothing);
    await choose(tester, 'Seleccionar archivo');
    expect(find.text('3 de 3'), findsOneWidget);
    expect(find.text('file4.pdf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'picker cancellation keeps the selection; concurrent taps cannot open two selectors',
      (tester) async {
    var calls = 0;
    final waiting = Completer<SelectedUpload?>();
    await mountSection(tester, initial: [sample('receipt.pdf')], pick: (_) {
      calls++;
      return waiting.future;
    });
    await tester.tap(find.byKey(const ValueKey('add-access-document')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tomar foto'));
    await tester.pump();
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('add-access-document')))
            .onPressed,
        isNull);
    waiting.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('1 de 3'), findsOneWidget);
    expect(find.text('receipt.pdf'), findsOneWidget);
    expect(calls, 1);
  });

  testWidgets(
      'oversize and mismatched types do not enter the list or remove valid files',
      (tester) async {
    var attempt = 0;
    await mountSection(tester,
        initial: [sample('receipt.pdf')],
        pick: (_) async => ++attempt == 1
            ? sample('large.jpg', size: FileService.maxDocumentBytes + 1)
            : sample('renamed.jpg', bytes: [37, 80, 68, 70, 45]));
    await choose(tester, 'Seleccionar archivo');
    expect(find.text('1 de 3'), findsOneWidget);
    expect(find.text('El archivo no puede superar 5 MB.'), findsOneWidget);
    dismissUploadError();
    await tester.pumpAndSettle();
    await choose(tester, 'Seleccionar archivo');
    expect(find.text('1 de 3'), findsOneWidget);
    expect(
        find.text('La extensión del archivo no coincide con su formato real.'),
        findsOneWidget);
    expect(find.text('receipt.pdf'), findsOneWidget);
  });

  testWidgets(
      'controls stay disabled while sending and long names wrap at large text scale',
      (tester) async {
    await mountSection(tester,
        pick: (_) async => sample('new.jpg'),
        enabled: false,
        scale: 2,
        initial: [sample('${'long-name' * 12}.jpg'), sample('receipt.pdf')]);
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('add-access-document')))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('remove-document-0')))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recoverable Android photo results obey the same maximum',
      (tester) async {
    await mountSection(tester,
        pick: (_) async => null,
        initial: [sample('original.pdf')],
        recover: () async => [
              sample('recovered1.jpg'),
              sample('recovered2.jpg'),
              sample('recovered3.jpg')
            ]);
    expect(find.text('3 de 3'), findsOneWidget);
    expect(find.text('original.pdf'), findsOneWidget);
    expect(find.text('recovered3.jpg'), findsNothing);
  });

  testWidgets(
      'administrative view reads and opens all three current documents using their own references',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final docs = [
      for (var i = 0; i < 3; i++)
        {
          'url': 'gs://demo/access_requests/fictional/identity/file$i.pdf',
          'storagePath': 'access_requests/fictional/identity/file$i.pdf',
          'name': 'file$i.pdf',
          'size': 1024,
          'contentType': 'application/pdf'
        }
    ];
    await db.doc('accessRequests/test').set(
        {'identityDocuments': docs, 'identityDocumentUrl': docs[0]['url']});
    final request =
        AccessRequest.fromFirestore(await db.doc('accessRequests/test').get());
    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AccessRequestDocumentLinks(
                request: request,
                open: (document) async {
                  opened.add(document.url);
                }))));
    expect(find.byType(OutlinedButton), findsNWidgets(3));
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('file$i.pdf'));
    }
    await tester.pumpAndSettle();
    expect(opened, docs.map((d) => d['url']).toList());
    expect(find.textContaining('gs://'), findsNothing);
  });

  testWidgets(
      'historical single-file requests still have exactly one working link without migration',
      (tester) async {
    final db = FakeFirebaseFirestore();
    const url =
        'https://firebasestorage.googleapis.com/v0/b/demo/o/access_requests%2Ffictional%2Fidentity%2F123_receipt.pdf?alt=media&token=fictional';
    await db.doc('accessRequests/history').set({'identityDocumentUrl': url});
    final before = (await db.doc('accessRequests/history').get()).data();
    final request = AccessRequest.fromFirestore(
        await db.doc('accessRequests/history').get());
    var opened = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AccessRequestDocumentLinks(
                request: request,
                open: (file) async {
                  expect(file.url, url);
                  opened = true;
                }))));
    expect(find.byType(OutlinedButton), findsOneWidget);
    await tester.tap(find.text('receipt.pdf'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    expect((await db.doc('accessRequests/history').get()).data(), before);
  });

  testWidgets(
      'signup requires one document, removes only the lower back button, and keeps the form on failure',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(414, 1400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: SignupScreen(
            pickDocument: (_) async => sample('receipt.pdf'),
            submitRequest: (
                {required name,
                required dni,
                required phone,
                required email,
                required address,
                required timeLivingHere,
                required reason,
                required identityDocuments}) async {
              calls++;
              expect(identityDocuments.length, 1);
              throw const AuthFlowException('Fallo ficticio de subida.');
            })));
    expect(find.text('Volver atrás'), findsNothing);
    final fields = find.byType(TextFormField);
    const values = [
      'Fictional Applicant',
      '00000001',
      '000000001',
      'applicant@example.com',
      'Fictional address',
      'Fictional application'
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
    final send = find.text('Enviar solicitud');
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Adjunta un documento de respaldo.'), findsOneWidget);
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .hideCurrentSnackBar();
    await tester.pumpAndSettle();
    await choose(tester, 'Seleccionar archivo');
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Fallo ficticio de subida.'), findsOneWidget);
    expect(find.text('1 de 3'), findsOneWidget);
    expect(find.text('receipt.pdf'), findsOneWidget);
    expect(tester.widget<TextFormField>(fields.first).controller!.text,
        values.first);
    expect(tester.takeException(), isNull);
  });
}
