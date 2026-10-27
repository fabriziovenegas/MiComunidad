import 'package:flutter/material.dart';
import '../models/user_model.dart';
import 'project_presentation.dart';
import 'report_presentation.dart';
import 'agenda_presentation.dart';

/// Only explicitly selected reading fields are displayed by each content type.
class ContentInformation extends StatelessWidget {
  const ContentInformation({
    super.key,
    required this.collection,
    required this.data,
    this.documentId,
    this.reportId,
    this.user,
  });

  final String collection;
  final Map<String, dynamic> data;
  final String? documentId;
  final String? reportId;
  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    if (collection == 'projects') {
      return ProjectInformation(data: data, projectId: documentId, user: user);
    }
    if (collection == 'reports') {
      return ReportInformation(
          data: data, reportId: reportId ?? documentId, user: user);
    }
    if (collection == 'events') {
      return AgendaInformation(data: data, eventId: documentId, user: user);
    }
    return const SizedBox.shrink();
  }
}
