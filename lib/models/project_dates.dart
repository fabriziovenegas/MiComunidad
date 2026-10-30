import 'package:cloud_firestore/cloud_firestore.dart';

class ProjectDates {
  static DateTime? date(Object? value) =>
      value is Timestamp ? value.toDate() : null;
  static bool valid(Map<String, dynamic> data) {
    final start = data['startDate'], end = data['expectedEndDate'];
    return (start == null || start is Timestamp) &&
        (end == null || end is Timestamp) &&
        (start == null ||
            end == null ||
            (start as Timestamp).compareTo(end as Timestamp) <= 0);
  }
}
