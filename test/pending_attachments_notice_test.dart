import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:micomunidad/services/attachment_delivery.dart';
import 'package:micomunidad/services/pending_upload_service.dart';
import 'package:micomunidad/widgets/pending_attachments_notice.dart';

class NoticeUploads extends Mock implements PendingUploadService {
  List<PendingAttachment> items = [];
  final changes = StreamController<List<PendingAttachment>>.broadcast();

  @override
  Stream<List<PendingAttachment>> watch(String userId) async* {
    yield items;
    yield* changes.stream;
  }

  void update(List<PendingAttachment> value) {
    items = value;
    changes.add(value);
  }
}

PendingAttachment attachment(String id, String kind,
        {String collection = 'events', String parent = 'activity'}) =>
    PendingAttachment(
        id: id,
        collection: collection,
        documentId: parent,
        kind: kind,
        localPath: '/local/$id',
        name: '$id.${kind == 'minutes' ? 'pdf' : 'jpg'}',
        userId: 'fictional-owner');

void main() {
  late NoticeUploads uploads;
  setUp(() => uploads = NoticeUploads());
  tearDown(() => uploads.changes.close());

  Widget notice({String? kind, String? parent = 'activity'}) => MaterialApp(
      home: Scaffold(
          body: PendingAttachmentsNotice(
              collection: 'events',
              documentId: parent,
              kind: kind,
              userId: 'fictional-owner',
              service: uploads)));

  for (final kind in ['photos', 'minutes']) {
    testWidgets('$kind section shows only its own pending attachments',
        (tester) async {
      uploads.items = [
        attachment('photo', 'photos'),
        attachment('acta', 'minutes'),
        attachment('other-activity', kind, parent: 'other'),
        attachment('other-collection', kind, collection: 'projects'),
      ];
      await tester.pumpWidget(notice(kind: kind));
      await tester.pumpAndSettle();
      expect(find.text('1 archivo pendiente de envío'), findsOneWidget);
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(find.text(kind == 'photos' ? 'photo.jpg' : 'acta.pdf'),
          findsOneWidget);
      expect(
          find.text(kind == 'photos' ? 'acta.pdf' : 'photo.jpg'), findsNothing);
      expect(find.textContaining('other-activity.'), findsNothing);
      expect(find.textContaining('other-collection.'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('collection-wide notice still includes photos and minutes',
      (tester) async {
    uploads.items = [
      attachment('photo', 'photos'),
      attachment('acta', 'minutes'),
      attachment('other-activity', 'photos', parent: 'other'),
    ];
    await tester.pumpWidget(notice(parent: null));
    await tester.pumpAndSettle();
    expect(find.text('3 archivos pendientes de envío'), findsOneWidget);
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.text('acta.pdf'), findsOneWidget);
    expect(find.text('other-activity.jpg'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('confirmed photo disappears without hiding a still pending acta',
      (tester) async {
    final photo = attachment('photo', 'photos');
    final acta = attachment('acta', 'minutes');
    uploads.items = [photo, acta];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      for (final kind in ['photos', 'minutes'])
        PendingAttachmentsNotice(
            key: ValueKey(kind),
            collection: 'events',
            documentId: 'activity',
            kind: kind,
            userId: 'fictional-owner',
            service: uploads),
    ]))));
    await tester.pumpAndSettle();
    expect(find.text('1 archivo pendiente de envío'), findsNWidgets(2));
    uploads.update([acta]);
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('photos')),
            matching: find.byType(Card)),
        findsNothing);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('minutes')),
            matching: find.text('1 archivo pendiente de envío')),
        findsOneWidget);
    uploads.update([]);
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('changing section kind refreshes the visible list',
      (tester) async {
    uploads.items = [
      attachment('photo', 'photos'),
      attachment('acta', 'minutes')
    ];
    await tester.pumpWidget(notice(kind: 'photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.text('photo.jpg'), findsOneWidget);
    await tester.pumpWidget(notice(kind: 'minutes'));
    await tester.pumpAndSettle();
    expect(find.text('acta.pdf'), findsOneWidget);
    expect(find.text('photo.jpg'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
