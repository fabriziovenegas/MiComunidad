import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/models/access_request.dart';
import 'package:micomunidad/widgets/access_request_document_links.dart';
import 'package:micomunidad/widgets/private_storage_image.dart';
import 'package:micomunidad/widgets/upload_error_notice.dart';

void main() {
  tearDown(dismissUploadError);
  testWidgets('offline photo retries successfully without exposing URLs',
      (tester) async {
    var offline = true;
    var reads = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 320,
                height: 300,
                child: PrivateStorageImage('gs://fictional/private',
                    isOffline: () async => offline,
                    read: (_) async {
                      reads++;
                      return base64Decode(
                          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
                    })))));
    await tester.pumpAndSettle();
    expect(reads, 0);
    expect(find.text('No se pudo cargar la fotografía. Verifica tu conexión'),
        findsOneWidget);
    offline = false;
    dismissUploadError();
    await tester.pump();
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Reintentar'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'stalled photo ends loading after 30s and retry starts a fresh read',
      (tester) async {
    var reads = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 100,
                height: 100,
                child: PrivateStorageImage('gs://fictional/private',
                    isOffline: () async => false,
                    read: (_) {
                      reads++;
                      return Completer<Uint8List>().future;
                    })))));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    expect(reads, 2);
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  Future<AccessRequest> request() async {
    final db = FakeFirebaseFirestore();
    await db.doc('accessRequests/test').set({
      'identityDocumentUrl':
          'gs://fictional/access_requests/test/identity/test.pdf'
    });
    return AccessRequest.fromFirestore(
        await db.doc('accessRequests/test').get());
  }

  testWidgets(
      'offline document shows red notice without starting open and allows retry',
      (tester) async {
    var calls = 0;
    var offline = true;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AccessRequestDocumentLinks(
                request: await request(),
                isOffline: () async => offline,
                open: (_) async {
                  calls++;
                }))));
    await tester.tap(find.text('test.pdf'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Necesitas conexión para abrir el documento'),
        findsOneWidget);
    offline = false;
    dismissUploadError();
    await tester.pump();
    await tester.tap(find.text('test.pdf'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Abriendo…'), findsNothing);
  });
  testWidgets(
      'slow document blocks duplicate taps, warns at 5s and recovers from failure',
      (tester) async {
    var calls = 0;
    final pending = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AccessRequestDocumentLinks(
                request: await request(),
                isOffline: () async => false,
                open: (_) {
                  calls++;
                  return calls == 1 ? pending.future : Future.value();
                }))));
    await tester.tap(find.text('test.pdf'));
    await tester.pump();
    expect(find.text('Abriendo…'), findsOneWidget);
    await tester.tap(find.text('Abriendo…'));
    await tester.pump(const Duration(seconds: 5));
    expect(calls, 1);
    expect(
        find.text(
            'El documento está tardando en abrirse. Verifica tu conexión'),
        findsOneWidget);
    pending.completeError(StateError('fictional failure'));
    await tester.pumpAndSettle();
    expect(find.text('Abriendo…'), findsNothing);
    expect(
        find.text(
            'No se pudo abrir el documento adjunto. Verifica tu conexión y vuelve a intentarlo.'),
        findsOneWidget);
    dismissUploadError();
    await tester.pump();
    await tester.tap(find.text('test.pdf'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });
}
