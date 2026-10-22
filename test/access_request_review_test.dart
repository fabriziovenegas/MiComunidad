import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/services/access_request_review.dart';

void main() {
  test('successful approval sends once, then returns the sent message',
      () async {
    final calls = <String>[];
    final result = await reviewAccessRequestWithEmail(
      approve: true,
      review: () async => calls.add('approve'),
      sendEmail: () async => calls.add('send'),
    );
    expect(calls, ['approve', 'send']);
    expect(result, AccessRequestReviewResult.approvedEmailSent);
    expect(result.message,
        'Vecino aprobado y cuenta creada. Se ha enviado un correo para establecer su contraseña.');
    expect(result.message, isNot(contains('entregado')));
    expect(result.message, isNot(contains('recibido')));
  });

  for (final error in [
    FirebaseAuthException(code: 'network-request-failed'),
    FirebaseAuthException(code: 'too-many-requests'),
    Exception('Simulated email failure'),
  ]) {
    test('email failure preserves approval and returns the warning: $error',
        () async {
      var approvals = 0;
      var sends = 0;
      final result = await reviewAccessRequestWithEmail(
        approve: true,
        review: () async => approvals++,
        sendEmail: () async {
          sends++;
          throw error;
        },
      );
      expect(approvals, 1);
      expect(sends, 1);
      expect(result, AccessRequestReviewResult.approvedEmailFailed);
      expect(result.message,
          'Vecino aprobado y cuenta creada, pero no se pudo enviar el correo. Puede solicitar un nuevo enlace desde «Recuperar contraseña».');
    });
  }

  test('approval failure propagates without sending any email', () async {
    final error = Exception('Simulated approval failure');
    var sends = 0;
    await expectLater(
      reviewAccessRequestWithEmail(
        approve: true,
        review: () async => throw error,
        sendEmail: () async => sends++,
      ),
      throwsA(same(error)),
    );
    expect(sends, 0);
  });

  test('rejection keeps the existing message and never sends a password email',
      () async {
    var reviews = 0;
    var sends = 0;
    final result = await reviewAccessRequestWithEmail(
      approve: false,
      review: () async => reviews++,
      sendEmail: () async => sends++,
    );
    expect(reviews, 1);
    expect(sends, 0);
    expect(result, AccessRequestReviewResult.rejected);
    expect(result.message, 'Solicitud rechazada.');
  });

  test('failed rejection remains an error, without a password email', () async {
    final error = Exception('Simulated rejection failure');
    await expectLater(
      reviewAccessRequestWithEmail(
        approve: false,
        review: () async => throw error,
        sendEmail: () async => fail('Rejection must not send a password email'),
      ),
      throwsA(same(error)),
    );
  });

  test('waits for backend approval and email result before selecting a message',
      () async {
    final approved = Completer<void>();
    final sent = Completer<void>();
    var sends = 0;
    var finished = false;
    final pending = reviewAccessRequestWithEmail(
      approve: true,
      review: () => approved.future,
      sendEmail: () {
        sends++;
        return sent.future;
      },
    ).then((result) {
      finished = true;
      return result;
    });
    await Future<void>.delayed(Duration.zero);
    expect(sends, 0);
    expect(finished, false);
    approved.complete();
    await Future<void>.delayed(Duration.zero);
    expect(sends, 1);
    expect(finished, false);
    sent.complete();
    expect(await pending, AccessRequestReviewResult.approvedEmailSent);
    expect(finished, true);
  });
}
