// Test-only SDK doubles: no production classes inherit these sealed interfaces.
// ignore_for_file: subtype_of_sealed_class, must_be_immutable
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:micomunidad/services/content_creation_draft.dart';

// Deliberately in-memory: no Firebase app, network or credentials are used.
class DraftDatabase extends Mock implements FirebaseFirestore {
  int allocated = 0;
  final documents = <DraftDocument>[];
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      DraftCollection(this);
}

class DraftCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {
  DraftCollection(this.db);
  final DraftDatabase db;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    final ref = DraftDocument(path ?? 'draft-${++db.allocated}');
    db.documents.add(ref);
    return ref;
  }
}

class DraftDocument extends Mock
    implements DocumentReference<Map<String, dynamic>> {
  DraftDocument(this.id);
  @override
  final String id;
  Map<String, dynamic>? saved;
  int writes = 0;
  int reads = 0;
  Object? readError;
  bool cached = false;
  bool pending = false;
  Future<void> Function(Map<String, dynamic>)? beforeWrite;
  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    writes++;
    if (beforeWrite != null) await beforeWrite!(data);
    saved = Map<String, dynamic>.from(data);
  }

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get(
      [GetOptions? options]) async {
    expect(options?.source, Source.server);
    reads++;
    if (readError != null) throw readError!;
    return DraftSnapshot(
        saved == null ? null : Map<String, dynamic>.from(saved!),
        cached: cached,
        pending: pending);
  }
}

class DraftSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {
  DraftSnapshot(this.row, {this.cached = false, this.pending = false});
  final Map<String, dynamic>? row;
  final bool cached;
  final bool pending;
  @override
  SnapshotMetadata get metadata => DraftMetadata(cached, pending);
  @override
  bool get exists => row != null;
  @override
  Map<String, dynamic>? data() => row;
}

class DraftMetadata extends Mock implements SnapshotMetadata {
  DraftMetadata(this.isFromCache, this.hasPendingWrites);
  @override
  final bool isFromCache;
  @override
  final bool hasPendingWrites;
}

void main() {
  const fields = {
    'title': 'Fictional title',
    'description': 'Fictional description',
    'location': 'Demo hall'
  };
  for (final collection in ['projects', 'reports', 'events']) {
    test('$collection saves confirmed content and the original metadata fields',
        () async {
      final db = DraftDatabase();
      final draft = ContentCreationDraft(
          collection: collection,
          firestore: db,
          currentUserId: () => 'demo-owner');
      await draft.save(fields);
      final ref = db.documents.single;
      expect(ref.writes, 1);
      expect(ref.saved!['title'], fields['title']);
      expect(ref.saved!['createdBy'], 'demo-owner');
      expect(ref.saved!['createdAt'], isA<FieldValue>());
      expect(ref.saved!['updatedAt'], isA<FieldValue>());
      if (collection == 'projects') expect(ref.saved!['isTrashed'], false);
      if (collection == 'reports') {
        expect(ref.saved!['status'], 'pendiente');
        expect(ref.saved!['moderationStatus'], 'pendiente');
      }
    });
    test(
        '$collection does not send again while the first confirmation is pending',
        () async {
      final db = DraftDatabase();
      final ack = Completer<void>();
      final draft = ContentCreationDraft(
          collection: collection,
          firestore: db,
          currentUserId: () => 'demo-owner');
      db.documents.single.beforeWrite = (_) => ack.future;
      var completed = false;
      final first = draft.save(fields).then((_) => completed = true);
      final second = draft.save(fields);
      await Future<void>.delayed(Duration.zero);
      expect(db.documents.single.writes, 1);
      expect(completed, false);
      ack.complete();
      await first;
      await second;
      expect(completed, true);
      expect(db.allocated, 1);
    });
    test(
        '$collection retries a rejected write using the same identifier and latest unsaved input',
        () async {
      final db = DraftDatabase();
      final draft = ContentCreationDraft(
          collection: collection,
          firestore: db,
          currentUserId: () => 'demo-owner');
      final ref = db.documents.single;
      ref.beforeWrite = (_) async => throw FirebaseException(
          plugin: 'cloud_firestore', code: 'unavailable');
      await expectLater(draft.save(fields), throwsA(isA<FirebaseException>()));
      final id = draft.id;
      expect(ref.saved, isNull);
      ref.beforeWrite = null;
      await draft.save({...fields, 'title': 'Corrected fictional title'});
      expect(draft.id, id);
      expect(db.allocated, 1);
      expect(ref.saved!['title'], 'Corrected fictional title');
      expect(ref.writes, 2);
    });
    test(
        '$collection recovers a lost response only after a matching server confirmation',
        () async {
      final db = DraftDatabase();
      final draft = ContentCreationDraft(
          collection: collection,
          firestore: db,
          currentUserId: () => 'demo-owner');
      final ref = db.documents.single;
      ref.beforeWrite = (data) async {
        ref.saved = Map.of(data);
        throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
      };
      await draft.save(fields);
      expect(ref.writes, 1);
      expect(ref.reads, 1);
      await draft.save(fields);
      expect(ref.writes, 1);
      expect(db.allocated, 1);
    });
    test(
        '$collection keeps uncertainty as an error and later confirms without a second write',
        () async {
      final db = DraftDatabase();
      final draft = ContentCreationDraft(
          collection: collection,
          firestore: db,
          currentUserId: () => 'demo-owner');
      final ref = db.documents.single;
      ref.readError =
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
      ref.beforeWrite = (data) async {
        ref.saved = Map.of(data);
        throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
      };
      await expectLater(draft.save(fields), throwsA(isA<FirebaseException>()));
      ref.readError = null;
      await draft.save(fields);
      expect(ref.writes, 1);
      expect(db.allocated, 1);
    });
    test('$collection never overwrites a confirmed record with different input',
        () async {
      final db = DraftDatabase();
      final draft = ContentCreationDraft(
          collection: collection,
          firestore: db,
          currentUserId: () => 'demo-owner');
      await draft.save(fields);
      final ref = db.documents.single;
      await expectLater(draft.save({...fields, 'title': 'Different title'}),
          throwsStateError);
      expect(ref.writes, 1);
      expect(ref.saved!['title'], fields['title']);
    });
  }
  test('a new intentional form gets its own ID, unlike a retry', () {
    final db = DraftDatabase();
    final one = ContentCreationDraft(
        collection: 'projects', firestore: db, currentUserId: () => 'demo');
    final two = ContentCreationDraft(
        collection: 'projects', firestore: db, currentUserId: () => 'demo');
    expect(one.id, isNot(two.id));
  });
  for (final cached in [true, false]) {
    test('cache or pending writes never count as confirmation (cached=$cached)',
        () async {
      final db = DraftDatabase();
      final draft = ContentCreationDraft(
          collection: 'reports',
          firestore: db,
          currentUserId: () => 'demo-owner');
      final ref = db.documents.single;
      ref.cached = cached;
      ref.pending = !cached;
      ref.beforeWrite = (data) async {
        ref.saved = Map.of(data);
        throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
      };
      await expectLater(draft.save(fields), throwsA(isA<FirebaseException>()));
      expect(ref.writes, 1);
      ref.cached = false;
      ref.pending = false;
      await draft.save(fields);
      expect(ref.writes, 1);
    });
  }
  test('a changed or signed-out account cannot send another account\'s draft',
      () async {
    final db = DraftDatabase();
    String? user = 'demo-owner';
    final draft = ContentCreationDraft(
        collection: 'projects',
        firestore: db,
        expectedUserId: user,
        currentUserId: () => user);
    user = 'another-demo';
    await expectLater(draft.save(fields), throwsStateError);
    user = null;
    await expectLater(draft.save(fields), throwsStateError);
    expect(db.documents.single.writes, 0);
  });
  test(
      'a hidden nonexistent report does not require broader Firestore read rules to retry',
      () async {
    final db = DraftDatabase();
    final draft = ContentCreationDraft(
        collection: 'reports',
        firestore: db,
        currentUserId: () => 'demo-owner');
    final ref = db.documents.single;
    ref.beforeWrite = (_) async =>
        throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    await expectLater(draft.save(fields), throwsA(isA<FirebaseException>()));
    ref.readError =
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
    ref.beforeWrite = null;
    await draft.save(fields);
    expect(ref.saved!['createdBy'], 'demo-owner');
    expect(db.allocated, 1);
  });
  test('missing read permission for projects never becomes a blind overwrite',
      () async {
    final db = DraftDatabase();
    final draft = ContentCreationDraft(
        collection: 'projects',
        firestore: db,
        currentUserId: () => 'demo-owner');
    await draft.save(fields);
    final ref = db.documents.single;
    ref.readError =
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
    await expectLater(draft.save(fields), throwsA(isA<FirebaseException>()));
    expect(ref.writes, 1);
  });
}
