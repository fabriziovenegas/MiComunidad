import 'user_model.dart';

/// Content fields that an author may edit without changing administration data.
class ReportEditDraft {
  const ReportEditDraft({
    required this.title,
    required this.description,
    required this.location,
    required this.category,
    required this.priority,
  });

  static const maxTitleLength = 160;
  static const maxDescriptionLength = 4000;
  static const maxLocationLength = 300;
  static const categories = [
    'seguridad',
    'obras',
    'iluminacion',
    'limpieza',
    'otro',
  ];
  static const priorities = ['baja', 'media', 'alta'];

  final String title;
  final String description;
  final String location;
  final String category;
  final String priority;

  static String? validateTitle(String? value) =>
      _requiredText(value, maxTitleLength);
  static String? validateDescription(String? value) =>
      _requiredText(value, maxDescriptionLength);
  static String? validateLocation(String? value) =>
      (value ?? '').trim().length > maxLocationLength
          ? 'Usa como máximo $maxLocationLength caracteres.'
          : null;

  static String? _requiredText(String? value, int maxLength) {
    if (value == null || value.trim().isEmpty) {
      return 'Este campo es obligatorio.';
    }
    return value.trim().length > maxLength
        ? 'Usa como máximo $maxLength caracteres.'
        : null;
  }

  String? get validationError =>
      validateTitle(title) ??
      validateDescription(description) ??
      validateLocation(location) ??
      (!categories.contains(category)
          ? 'Selecciona una categoría válida.'
          : null) ??
      (!priorities.contains(priority)
          ? 'Selecciona una prioridad válida.'
          : null);

  Map<String, dynamic> toUpdateData() => {
        'title': title.trim(),
        'description': description.trim(),
        'location': location.trim(),
        'category': category,
        'priority': priority,
      };
}

bool reportContentIsEditable(Map<String, dynamic> report) =>
    report['deletionInProgress'] != true &&
    const ['pendiente', 'aprobado'].contains(report['moderationStatus']) &&
    const ['pendiente', 'en_revision', 'en_proceso'].contains(report['status']);

bool reportIsApprovedResolved(Map<String, dynamic> report) =>
    report['deletionInProgress'] != true &&
    report['moderationStatus'] == 'aprobado' &&
    report['status'] == 'resuelto';

bool reportAcceptsComments(Map<String, dynamic> report) =>
    report['deletionInProgress'] != true &&
    report['moderationStatus'] == 'aprobado' &&
    const ['pendiente', 'en_revision', 'en_proceso', 'resuelto']
        .contains(report['status']);

bool canUserCommentOnReport(AppUser user, Map<String, dynamic> report) =>
    user.isApproved &&
    (user.isAdmin || user.isNeighbor) &&
    reportAcceptsComments(report);

bool canEditOwnActiveReport(Map<String, dynamic> report, String userId) =>
    userId.isNotEmpty &&
    report['createdBy'] == userId &&
    reportContentIsEditable(report);

bool isApprovedReportAuthor(AppUser user, Map<String, dynamic> report,
        String? authenticatedUserId) =>
    user.isApproved &&
    (user.isNeighbor || user.isAdmin) &&
    authenticatedUserId != null &&
    authenticatedUserId.isNotEmpty &&
    report['createdBy'] == authenticatedUserId;

bool canUserEditReportContent(AppUser user, Map<String, dynamic> report,
        String? authenticatedUserId) =>
    isApprovedReportAuthor(user, report, authenticatedUserId) &&
    (reportContentIsEditable(report) ||
        (user.isAdmin && reportIsApprovedResolved(report)));

bool reportUsesStatusOnlyDialog(AppUser user, Map<String, dynamic> report,
        String? authenticatedUserId) =>
    canAdminChangeReportStatus(user, report) &&
    !isApprovedReportAuthor(user, report, authenticatedUserId);

bool canAdminChangeReportStatus(AppUser user, Map<String, dynamic> report) =>
    user.isApproved &&
    user.isAdmin &&
    report['deletionInProgress'] != true &&
    report['moderationStatus'] == 'aprobado';

bool canUserManageReport(AppUser user, Map<String, dynamic> report,
        String? authenticatedUserId) =>
    canUserEditReportContent(user, report, authenticatedUserId) ||
    canAdminChangeReportStatus(user, report);
