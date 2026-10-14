import 'package:flutter_test/flutter_test.dart';
import 'package:micomunidad/models/report_edit.dart';
import 'package:micomunidad/models/user_model.dart';

AppUser user(UserRole role, {String approval = 'aprobado'}) => AppUser(
      userId: 'author-demo',
      email: 'resident@example.com',
      nombre: 'Demo Resident',
      role: role,
      approvalStatus: approval,
      joinDate: DateTime.utc(2026, 1, 1),
      communityId: 'demo',
      createdAt: DateTime.utc(2026, 1, 1),
    );

Map<String, dynamic> report({
  String author = 'author-demo',
  String moderation = 'aprobado',
  String status = 'pendiente',
}) =>
    {
      'createdBy': author,
      'moderationStatus': moderation,
      'status': status,
    };

void main() {
  test(
      'administrator keeps the preview action on own and other resolved reports',
      () {
    for (final author in ['author-demo', 'another-demo']) {
      final resolved = report(author: author, status: 'resuelto');
      expect(canUserManageReport(user(UserRole.admin), resolved, 'author-demo'),
          isTrue);
      expect(
          canUserEditReportContent(
              user(UserRole.admin), resolved, 'author-demo'),
          author == 'author-demo');
      expect(
          canUserManageReport(user(UserRole.vecino), resolved, 'author-demo'),
          isFalse);
    }
  });

  test('administrator can manage another active report but cannot edit content',
      () {
    final another = report(author: 'another-demo', status: 'en_proceso');
    expect(canUserManageReport(user(UserRole.admin), another, 'author-demo'),
        isTrue);
    expect(isApprovedReportAuthor(user(UserRole.admin), another, 'author-demo'),
        isFalse);
  });

  for (final role in UserRole.values) {
    for (final moderation in ['pendiente', 'aprobado']) {
      for (final status in ['pendiente', 'en_revision', 'en_proceso']) {
        test('${role.name} can edit own $moderation/$status content', () {
          expect(
              canUserEditReportContent(
                  user(role),
                  report(moderation: moderation, status: status),
                  'author-demo'),
              isTrue);
        });
      }
    }
    test('${role.name} cannot edit another author or without approval/session',
        () {
      expect(
          canUserEditReportContent(
              user(role), report(author: 'another-demo'), 'author-demo'),
          isFalse);
      expect(canUserEditReportContent(user(role), report(), null), isFalse);
      expect(canUserEditReportContent(user(role), report(), ''), isFalse);
      expect(
          canUserEditReportContent(
              user(role, approval: 'pendiente'), report(), 'author-demo'),
          isFalse);
    });
    test('${role.name} follows resolved-owner exception but not rejection', () {
      expect(
          canUserEditReportContent(
              user(role), report(status: 'resuelto'), 'author-demo'),
          role == UserRole.admin);
      expect(
          canUserEditReportContent(
              user(role), report(moderation: 'rechazado'), 'author-demo'),
          isFalse);
    });
  }

  test('administrator state action is independent from report authorship', () {
    for (final author in ['author-demo', 'another-demo']) {
      for (final status in ['pendiente', 'en_proceso', 'resuelto']) {
        final data = report(author: author, status: status);
        expect(canAdminChangeReportStatus(user(UserRole.admin), data), isTrue);
        expect(
            canAdminChangeReportStatus(user(UserRole.vecino), data), isFalse);
      }
    }
  });

  test('non-author administrators use only the state selector', () {
    for (final status in ['pendiente', 'en_proceso', 'resuelto']) {
      expect(
          reportUsesStatusOnlyDialog(user(UserRole.admin),
              report(author: 'another-demo', status: status), 'author-demo'),
          isTrue);
      expect(
          reportUsesStatusOnlyDialog(
              user(UserRole.admin), report(status: status), 'author-demo'),
          isFalse);
      expect(
          reportUsesStatusOnlyDialog(user(UserRole.vecino),
              report(author: 'another-demo', status: status), 'author-demo'),
          isFalse);
    }
  });

  test('state action preserves the existing approved-only moderation flow', () {
    for (final moderation in ['pendiente', 'rechazado']) {
      expect(
          canAdminChangeReportStatus(
              user(UserRole.admin), report(moderation: moderation)),
          isFalse);
    }
    expect(
        canAdminChangeReportStatus(
            user(UserRole.admin, approval: 'pendiente'), report()),
        isFalse);
  });
}
