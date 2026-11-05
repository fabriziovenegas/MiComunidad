import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/services/access_request_review.dart';
import 'package:micomunidad/services/review_wait_feedback.dart';
import 'package:micomunidad/widgets/upload_error_notice.dart';

void main() {
  tearDown(dismissUploadError);

  for (final report in [true, false]) {
    for (final approve in [true, false]) {
      final label = '${report ? 'report' : 'request'} / $approve';
      for (final code in [
        'unavailable',
        'permission-denied',
        'not-found',
        'unauthenticated',
        'deadline-exceeded'
      ]) {
        for (final delay in [Duration.zero, const Duration(seconds: 6)]) {
          testWidgets('$label: $code after $delay replaces warning with error',
              (tester) async {
            final completion = Completer<void>();
            late BuildContext noticeContext;
            await tester
                .pumpWidget(MaterialApp(home: Builder(builder: (context) {
              noticeContext = context;
              return const Scaffold();
            })));
            var calls = 0;
            var success = false;
            final error = report
                ? FirebaseException(plugin: 'cloud_firestore', code: code)
                : FirebaseFunctionsException(
                    code: code, message: 'Fictional error');
            final operation = waitForReview(
              action: () {
                calls++;
                return completion.future;
              },
              onSlow: () => showWarningNotice(noticeContext,
                  reviewWaitingMessage(approve: approve, isReport: report)),
            ).then((_) {
              success = true;
            }, onError: (Object actual) {
              expect(actual, same(error));
              showUploadError(noticeContext, 'Acción no confirmada');
            });
            if (delay != Duration.zero) {
              await tester.pump(delay);
              await tester.pump();
              expect(find.byKey(const ValueKey('save-warning-notice')),
                  findsOneWidget);
            }
            completion.completeError(error);
            await operation;
            await tester.pump();
            expect(find.byKey(const ValueKey('upload-error-notice')),
                findsOneWidget);
            expect(find.byKey(const ValueKey('save-warning-notice')),
                findsNothing);
            expect(find.byKey(const ValueKey('save-success-notice')),
                findsNothing);
            expect(success, isFalse);
            expect(calls, 1);
            dismissUploadError();
            await tester.pump(const Duration(seconds: 30));
            expect(find.byKey(const ValueKey('save-warning-notice')),
                findsNothing);
            expect(tester.takeException(), isNull);
          });
        }
      }

      testWidgets(
          '$label: disconnected wait neither cancels nor resends action',
          (tester) async {
        final completion = Completer<void>();
        var calls = 0;
        var warnings = 0;
        var confirmed = false;
        final operation = waitForReview(
          action: () {
            calls++;
            return completion.future;
          },
          onSlow: () => warnings++,
        ).then((_) => confirmed = true);
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(minutes: 2));
        expect(calls, 1);
        expect(warnings, 1);
        expect(confirmed, isFalse);
        completion.complete();
        await operation;
        expect(confirmed, isTrue);
        expect(calls, 1);
      });

      for (final leaveAfterWarning in [false, true]) {
        testWidgets('$label: leaving screen is safe ($leaveAfterWarning)',
            (tester) async {
          final completion = Completer<void>();
          late BuildContext screenContext;
          await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
            screenContext = context;
            return const Scaffold();
          })));
          final operation = waitForReview(
            action: () => completion.future,
            onSlow: () {
              if (screenContext.mounted) {
                showWarningNotice(screenContext,
                    reviewWaitingMessage(approve: approve, isReport: report));
              }
            },
          ).then((_) {
            if (screenContext.mounted) {
              showSuccessNotice(screenContext, 'Confirmado');
            }
          });
          if (leaveAfterWarning) {
            await tester.pump(const Duration(seconds: 5));
            await tester.pump();
            expect(find.byKey(const ValueKey('save-warning-notice')),
                findsOneWidget);
          }
          await tester.pumpWidget(const SizedBox());
          expect(screenContext.mounted, isFalse);
          await tester.pump(const Duration(seconds: 15));
          completion.complete();
          await operation;
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.text('Confirmado'), findsNothing);
        });
      }

      testWidgets('$label: confirmation just before threshold cancels warning',
          (tester) async {
        final completion = Completer<void>();
        var warnings = 0;
        final operation = waitForReview(
            action: () => completion.future, onSlow: () => warnings++);
        await tester.pump(const Duration(milliseconds: 4999));
        completion.complete();
        await operation;
        await tester.pump(const Duration(seconds: 10));
        expect(warnings, 0);
      });

      testWidgets('$label: only amber after 5s, then confirmed green',
          (tester) async {
        final completion = Completer<void>();
        late Future<void> operation;
        late BuildContext noticeContext;
        await tester.pumpWidget(MaterialApp(
          home: Builder(builder: (context) {
            noticeContext = context;
            return const Scaffold();
          }),
        ));
        operation = waitForReview(
          action: () => completion.future,
          onSlow: () => showWarningNotice(noticeContext,
              reviewWaitingMessage(approve: approve, isReport: report)),
        ).then((_) => showSuccessNotice(noticeContext, 'Confirmado'));
        await tester.pump(const Duration(seconds: 4));
        expect(find.byKey(const ValueKey('save-warning-notice')), findsNothing);
        expect(find.text('Confirmado'), findsNothing);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(
            find.byKey(const ValueKey('save-warning-notice')), findsOneWidget);
        expect(
            find.text(reviewWaitingMessage(approve: approve, isReport: report)),
            findsOneWidget);
        if (!report) {
          expect(find.textContaining('pendiente de envío'), findsNothing);
        }
        completion.complete();
        await operation;
        await tester.pump();
        expect(find.byKey(const ValueKey('save-warning-notice')), findsNothing);
        expect(
            find.byKey(const ValueKey('save-success-notice')), findsOneWidget);
        dismissUploadError();
        await tester.pump(const Duration(seconds: 20));
        expect(find.byKey(const ValueKey('save-warning-notice')), findsNothing);
      });

      testWidgets('$label: confirmed before 5s never shows pending',
          (tester) async {
        var notices = 0;
        final completion = Completer<void>();
        final operation = waitForReview(
            action: () => completion.future, onSlow: () => notices++);
        await tester.pump(const Duration(seconds: 4));
        completion.complete();
        await operation;
        await tester.pump(const Duration(seconds: 20));
        expect(notices, 0);
      });
    }
  }

  testWidgets('failed review cancels timer and never sends password email',
      (tester) async {
    var slow = 0;
    var emails = 0;
    final completion = Completer<void>();
    final operation = reviewAccessRequestWithEmail(
      approve: true,
      review: () =>
          waitForReview(action: () => completion.future, onSlow: () => slow++),
      sendEmail: () async {
        emails++;
      },
    );
    final failure = expectLater(operation, throwsStateError);
    completion.completeError(StateError('fictional failure'));
    await failure;
    await tester.pump(const Duration(seconds: 20));
    expect(slow, 0);
    expect(emails, 0);
  });

  testWidgets('waiting on password email does not report approval pending',
      (tester) async {
    final email = Completer<void>();
    var slow = 0;
    final operation = reviewAccessRequestWithEmail(
      approve: true,
      review: () => waitForReview(action: () async {}, onSlow: () => slow++),
      sendEmail: () => email.future,
    );
    await tester.pump(const Duration(seconds: 20));
    expect(slow, 0);
    email.complete();
    expect(await operation, AccessRequestReviewResult.approvedEmailSent);
  });
}
