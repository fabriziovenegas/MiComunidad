import 'package:cloud_firestore/cloud_firestore.dart';

/// A new record or comment keeps its identity for the whole delivery lifecycle.
class PendingContent {
  PendingContent(
      {required this.id,
      required this.collection,
      required this.userId,
      required Map<String, dynamic> fields,
      this.parentId,
      this.sent = false,
      this.blocked = false,
      this.reason})
      : fields = Map.unmodifiable(fields);
  final String id;
  final String collection;
  final String userId;
  final String? parentId;
  final Map<String, dynamic> fields;
  bool sent;
  bool blocked;
  String? reason;
  bool get isComment => parentId != null;
  String get path =>
      isComment ? '$collection/$parentId/comments/$id' : '$collection/$id';
  String get label => (fields[isComment ? 'text' : 'title'] as String?) ?? '';

  void validate() {
    bool safe(String value) =>
        RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(value);
    if (!safe(id) ||
        userId.isEmpty ||
        !const ['projects', 'events', 'reports'].contains(collection) ||
        (!isComment && collection == 'reports') ||
        (parentId != null && !safe(parentId!))) {
      throw const FormatException('Invalid pending content');
    }
    final allowed = isComment
        ? {'text', 'authorName'}
        : collection == 'projects'
            ? {'title', 'location', 'description', 'progress', 'status'}
            : {'title', 'location', 'description', 'eventDate'};
    if (!fields.keys.toSet().containsAll(allowed) ||
        fields.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('Unexpected pending fields');
    }
    if (isComment) {
      if (fields['text'] is! String ||
          (fields['text'] as String).trim().isEmpty ||
          (fields['text'] as String).length > 1000 ||
          fields['authorName'] is! String) {
        throw ArgumentError('Escribe entre 1 y 1000 caracteres.');
      }
    } else {
      if (fields['title'] is! String ||
          (fields['title'] as String).trim().isEmpty ||
          fields['description'] is! String ||
          fields['location'] is! String) {
        throw ArgumentError('Revisa los datos del formulario.');
      }
      if (collection == 'projects') {
        final progress = fields['progress'];
        if ((fields['description'] as String).trim().isEmpty ||
            progress is! int ||
            progress < 0 ||
            progress > 100 ||
            !const ['pendiente', 'en_proceso', 'finalizado']
                .contains(fields['status'])) {
          throw ArgumentError('Revisa la descripción, el avance y el estado.');
        }
      } else if (fields['eventDate'] is! Timestamp) {
        throw ArgumentError('La fecha no es válida.');
      }
    }
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'id': id,
        'collection': collection,
        'userId': userId,
        'parentId': parentId,
        'sent': sent,
        'blocked': blocked,
        'reason': reason,
        'fields': fields.map((key, value) => MapEntry(
            key,
            value is Timestamp
                ? {
                    'timestamp': [value.seconds, value.nanoseconds]
                  }
                : value)),
      };
  factory PendingContent.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unknown pending version');
    }
    final fields = Map<String, dynamic>.from(json['fields'] as Map);
    if (fields['eventDate'] case final Map value) {
      final parts = value['timestamp'] as List;
      fields['eventDate'] = Timestamp(parts[0] as int, parts[1] as int);
    }
    final item = PendingContent(
        id: json['id'] as String,
        collection: json['collection'] as String,
        userId: json['userId'] as String,
        parentId: json['parentId'] as String?,
        fields: fields,
        sent: json['sent'] == true,
        blocked: json['blocked'] == true,
        reason: json['reason'] as String?);
    item.validate();
    return item;
  }
}
