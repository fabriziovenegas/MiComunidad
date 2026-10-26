import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/services/pending_content_service.dart';
import 'package:micomunidad/services/content_delivery.dart';
import 'package:micomunidad/widgets/pending_content_notice.dart';
import 'package:micomunidad/widgets/content_comment_composer.dart';
import 'package:micomunidad/widgets/upload_error_notice.dart';

class NoticeDelivery implements ContentDelivery {
  Object? error;
  int calls = 0;
  @override
  Future<void> deliver(PendingContent item) async {
    calls++;
    if (error != null) throw error!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late NoticeDelivery delivery;
  late PendingContentService service;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pending-content-ui-');
    delivery = NoticeDelivery();
    service = PendingContentService(
        directory: () async => directory,
        currentUserId: () => 'owner',
        delivery: delivery);
  });
  tearDown(() async {
    dismissUploadError();
    final path = await directory.resolveSymbolicLinks();
    expect(path, contains('pending-content-ui-'));
    await Directory(path).delete(recursive: true);
  });
  Future<void> pumpIO(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pumpAndSettle();
  }

  Future<void> seed(
          {String collection = 'projects',
          String? parentId,
          String id = 'one'}) =>
      service
          .submit(
              id: id,
              collection: collection,
              expectedUserId: 'owner',
              parentId: parentId,
              fields: parentId == null
                  ? {
                      'title': 'Proyecto ficticio',
                      'description': 'Descripción de prueba',
                      'location': 'Local',
                      'progress': 24,
                      'status': 'pendiente'
                    }
                  : {
                      'text': 'Mi propuesta pendiente',
                      'authorName': 'Persona ficticia'
                    })
          .then((_) {});
  testWidgets(
      'pending project survives reopening its notice and disappears after retry confirms delivery',
      (tester) async {
    delivery.error =
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    await tester.runAsync(() => seed());
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PendingContentNotice(
                userId: 'owner', collection: 'projects', service: service))));
    await pumpIO(tester);
    expect(find.text('1 proyecto pendiente de envío'), findsOneWidget);
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.text('Proyecto ficticio'), findsOneWidget);
    delivery.error = null;
    await tester.tap(find.text('Reintentar'));
    await pumpIO(tester);
    expect(find.byType(Card), findsNothing);
    expect(await tester.runAsync(() => service.pendingFor('owner')), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('notice filters another account and comments on another parent',
      (tester) async {
    delivery.error =
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    await tester.runAsync(() => seed(parentId: 'parent-a'));
    await tester.pumpWidget(MaterialApp(
        home: Column(children: [
      PendingContentNotice(
          userId: 'other',
          collection: 'projects',
          parentId: 'parent-a',
          service: service),
      PendingContentNotice(
          userId: 'owner',
          collection: 'projects',
          parentId: 'parent-b',
          service: service)
    ])));
    await pumpIO(tester);
    expect(find.byType(Card), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  for (final state in [
    PendingSendState.queued,
    PendingSendState.blocked,
    PendingSendState.sent
  ]) {
    testWidgets(
        'composer communicates $state without calling a queued comment published',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ContentCommentComposer(
                  onSendPending: (_) async => PendingSendResult(state,
                      reason: 'No tienes permiso.')))));
      await tester.enterText(find.byType(TextField), 'Comentario ficticio');
      await tester.tap(find.byTooltip('Enviar comentario'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty);
      if (state == PendingSendState.sent) {
        expect(find.text('Comentario publicado.'), findsOneWidget);
      } else {
        expect(find.text('Comentario publicado.'), findsNothing);
        expect(find.textContaining('Comentario guardado'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
