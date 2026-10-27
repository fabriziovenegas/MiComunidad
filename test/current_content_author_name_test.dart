import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/models/user_model.dart';
import 'package:micomunidad/widgets/current_content_author_name.dart';
import 'package:micomunidad/widgets/content_information.dart';
import 'package:micomunidad/widgets/project_presentation.dart';
import 'package:micomunidad/widgets/agenda_presentation.dart';
import 'current_report_author_name_test.dart' show viewer;

Future<void> present(WidgetTester tester, Widget child,
    {double width = 412, double scale = 1}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Scaffold(
          body: SingleChildScrollView(
              padding: const EdgeInsets.all(20), child: child))));
}

void main() {
  for (final collection in ['projects', 'events']) {
    testWidgets(
        '$collection displays only the current author name after lookup',
        (tester) async {
      final pending = Completer<String?>();
      await present(
          tester,
          CurrentContentAuthorName(
              collection: collection,
              contentId: 'demo',
              authorId: 'other',
              savedName: 'Nombre anterior',
              viewer: viewer(),
              loadName: (kind, id) {
                expect(kind, collection);
                expect(id, 'demo');
                return pending.future;
              }));
      expect(find.text('Creado por Nombre anterior'), findsOneWidget);
      pending.complete('Nombre actual');
      await tester.pumpAndSettle();
      expect(find.text('Creado por Nombre actual'), findsOneWidget);
      expect(find.text('Creado por Nombre anterior'), findsNothing);
      expect(find.text('other'), findsNothing);
    });

    for (final role in [UserRole.admin, UserRole.vecino]) {
      testWidgets('$collection own creator follows profile changes for $role',
          (tester) async {
        var calls = 0;
        Future<String?> load(String _, String __) async {
          calls++;
          return 'Not used';
        }

        Widget author(String name) => CurrentContentAuthorName(
            collection: collection,
            contentId: 'demo',
            authorId: 'viewer-demo',
            viewer: viewer(name: name, role: role),
            loadName: load);
        await present(tester, author('Nombre inicial'));
        expect(find.text('Creado por Nombre inicial'), findsOneWidget);
        await present(tester, author('Nombre corregido'));
        await tester.pumpAndSettle();
        expect(find.text('Creado por Nombre corregido'), findsOneWidget);
        expect(calls, 0);
      });
    }

    testWidgets(
        '$collection refreshes another creator on resume and keeps last name offline',
        (tester) async {
      String? name = 'Nombre inicial';
      var fail = false;
      var calls = 0;
      Future<String?> load(String _, String __) async {
        calls++;
        if (fail) throw StateError('No network');
        return name;
      }

      await present(
          tester,
          CurrentContentAuthorName(
              collection: collection,
              contentId: 'demo',
              authorId: 'other',
              viewer: viewer(),
              loadName: load));
      await tester.pumpAndSettle();
      expect(find.text('Creado por Nombre inicial'), findsOneWidget);
      name = 'Nombre corregido';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Creado por Nombre corregido'), findsOneWidget);
      fail = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Creado por Nombre corregido'), findsOneWidget);
      expect(calls, 3);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '$collection creator is below location only in expanded information',
        (tester) async {
      final data = <String, dynamic>{
        'title': 'Contenido ficticio',
        'location': 'Lugar de demostración',
        'description': 'Descripción de prueba',
        'status': 'en_proceso',
        'progress': 42,
        'createdBy': 'viewer-demo',
        'email': 'private@example.com',
        'dni': '00000001'
      };
      await present(
          tester,
          ContentInformation(
              collection: collection,
              documentId: 'demo',
              data: data,
              user: viewer(name: 'Nombre actual')));
      expect(find.text('Creado por Nombre actual'), findsOneWidget);
      expect(
          tester.getTopLeft(find.text('Lugar de demostración')).dy,
          lessThan(
              tester.getTopLeft(find.text('Creado por Nombre actual')).dy));
      expect(tester.getTopLeft(find.text('Creado por Nombre actual')).dy,
          lessThan(tester.getTopLeft(find.text('Descripción')).dy));
      expect(find.text('private@example.com'), findsNothing);
      expect(find.text('00000001'), findsNothing);
      await present(
          tester,
          collection == 'projects'
              ? ProjectPreviewCard(data: data, onOpen: () {})
              : AgendaPreviewCard(data: data, onOpen: () {}));
      expect(find.byType(CurrentContentAuthorName), findsNothing);
      expect(find.textContaining('Creado por'), findsNothing);
    });

    testWidgets(
        '$collection does not invent a creator for historical missing identity',
        (tester) async {
      var calls = 0;
      await present(
          tester,
          CurrentContentAuthorName(
              collection: collection,
              contentId: 'demo',
              authorId: '',
              viewer: viewer(),
              loadName: (_, __) async {
                calls++;
                return 'Not allowed';
              }));
      await tester.pumpAndSettle();
      expect(find.text('Autor no disponible'), findsOneWidget);
      expect(calls, 0);
    });
  }

  testWidgets(
      'old pending response cannot appear after changing content or account',
      (tester) async {
    final first = Completer<String?>(), second = Completer<String?>();
    Future<String?> load(String _, String id) =>
        id == 'first' ? first.future : second.future;
    await present(
        tester,
        CurrentContentAuthorName(
            collection: 'projects',
            contentId: 'first',
            authorId: 'old-author',
            viewer: viewer(),
            loadName: load));
    await present(
        tester,
        CurrentContentAuthorName(
            collection: 'events',
            contentId: 'second',
            authorId: 'new-author',
            viewer: viewer(id: 'second-viewer'),
            savedName: 'Segundo autor',
            loadName: load));
    first.complete('Nombre del contenido anterior');
    await tester.pumpAndSettle();
    expect(find.textContaining('Nombre del contenido anterior'), findsNothing);
    second.complete('Nombre del segundo autor');
    await tester.pumpAndSettle();
    expect(find.text('Creado por Nombre del segundo autor'), findsOneWidget);
  });

  testWidgets('long creator names wrap at 320 pixels with large text',
      (tester) async {
    await present(
        tester,
        ContentInformation(
            collection: 'projects',
            documentId: 'demo',
            data: const {
              'createdBy': 'viewer-demo',
              'location': 'Lugar ficticio'
            },
            user: viewer(
                name:
                    'Nombre ficticio con varios apellidos para comprobar el ajuste del texto')),
        width: 320,
        scale: 2);
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
  });
}
