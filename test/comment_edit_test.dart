import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:micomunidad/services/comment_content_editor.dart';
import 'package:micomunidad/widgets/comment_edit_dialog.dart';
import 'package:micomunidad/widgets/content_comment_tile.dart';

void main() {
  for (final collection in ['projects', 'events', 'reports']) {
    test('$collection edits only own text and keeps identity', () async {
      final db = FakeFirebaseFirestore();
      await db
          .doc('users/owner')
          .set({'role': 'vecino', 'approvalStatus': 'aprobado'});
      await db.doc('$collection/parent').set({
        'isTrashed': false,
        'moderationStatus': 'aprobado',
        'status': 'resuelto'
      });
      final ref = db.doc('$collection/parent/comments/comment');
      final original = {
        'text': 'Antes',
        'authorId': 'owner',
        'authorName': 'Persona',
        'createdAt': 'original'
      };
      await ref.set(original);
      final editor =
          CommentContentEditor(firestore: db, currentUserId: () => 'owner');
      Future<void> save(String text) => editor.save(
          collection: collection,
          documentId: 'parent',
          commentId: 'comment',
          originalText: 'Antes',
          text: text);
      await save('Después');
      final after = (await ref.get()).data()!;
      expect(after['text'], 'Después');
      for (final field in ['authorId', 'authorName', 'createdAt']) {
        expect(after[field], original[field]);
      }
      expect(after.containsKey('updatedAt'), true);
      await save('Después'); // Lost acknowledgement retry is harmless.
      await expectLater(save('Otro cambio'), throwsStateError);
      await db.doc('users/owner').update({'role': 'admin'});
      await ref.update({'authorId': 'other'});
      await expectLater(save('No permitido'), throwsStateError);
      await ref.delete();
      await expectLater(save('No recrear'), throwsStateError);
      expect((await ref.get()).exists, false);
    });
  }
  testWidgets('menu opens editing without triggering deletion', (tester) async {
    var edits = 0, deletes = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ContentCommentTile(
                author: 'Persona',
                text: 'Comentario',
                onEdit: () => edits++,
                onDelete: () => deletes++))));
    await tester.tap(find.byTooltip('Opciones del comentario'));
    await tester.pumpAndSettle();
    expect(find.text('Editar comentario'), findsOneWidget);
    await tester.tap(find.text('Editar comentario'));
    await tester.pumpAndSettle();
    expect(edits, 1);
    expect(deletes, 0);
  });
  testWidgets('edit dialog blocks invalid text and keeps draft after a failure',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CommentEditDialog(
                initialText: 'Original',
                onSave: (text) async {
                  calls++;
                  throw StateError('offline');
                }))));
    await tester.enterText(find.byType(TextFormField), 'a' * 1001);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.enterText(find.byType(TextFormField), '');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.enterText(find.byType(TextFormField), 'Texto corregido');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Texto corregido'), findsOneWidget);
    expect(find.textContaining('No se pudo guardar.'), findsOneWidget);
  });
}
