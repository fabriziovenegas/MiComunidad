import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/text_encoding.dart';

class AccessRequestDocument {
  const AccessRequestDocument(
      {required this.url,
      required this.name,
      this.storagePath = '',
      this.size,
      this.contentType});

  final String url;
  final String name;
  final String storagePath;
  final int? size;
  final String? contentType;

  static String nameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final segment = uri == null || uri.pathSegments.isEmpty
        ? ''
        : uri.pathSegments.last.split('/').last;
    return segment.replaceFirst(RegExp(r'^\d+_'), '').trim().isEmpty
        ? 'Documento adjunto'
        : segment.replaceFirst(RegExp(r'^\d+_'), '');
  }
}

class AccessRequest {
  const AccessRequest({
    required this.id,
    required this.applicantUid,
    required this.name,
    required this.dni,
    required this.phone,
    required this.email,
    required this.address,
    required this.timeLivingHere,
    required this.reason,
    required this.identityDocumentUrl,
    required this.status,
    required this.createdAt,
    this.rejectionReason,
    this.identityDocuments = const [],
  });

  final String id;
  final String applicantUid;
  final String name;
  final String dni;
  final String phone;
  final String email;
  final String address;
  final String timeLivingHere;
  final String reason;
  final String identityDocumentUrl;
  final String status;
  final DateTime createdAt;
  final String? rejectionReason;
  final List<AccessRequestDocument> identityDocuments;

  List<AccessRequestDocument> get documents => identityDocuments.isNotEmpty
      ? List.unmodifiable(identityDocuments)
      : identityDocumentUrl.isEmpty
          ? const []
          : [
              AccessRequestDocument(
                  url: identityDocumentUrl,
                  name: AccessRequestDocument.nameFromUrl(identityDocumentUrl))
            ];

  factory AccessRequest.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return AccessRequest(
      id: document.id,
      applicantUid: data['applicantUid'] as String? ?? '',
      name: readableText(data['name']),
      dni: data['dni'] as String? ?? '',
      phone: readableText(data['phone']),
      email: readableText(data['email']),
      address: readableText(data['address']),
      timeLivingHere: readableText(data['timeLivingHere']),
      reason: readableText(data['reason']),
      identityDocumentUrl: data['identityDocumentUrl'] as String? ?? '',
      identityDocuments: [
        for (final item in data['identityDocuments'] is List
            ? data['identityDocuments'] as List
            : const [])
          if (item is Map &&
              item['url'] is String &&
              (item['url'] as String).isNotEmpty)
            AccessRequestDocument(
              url: item['url'] as String,
              name: item['name'] is String &&
                      (item['name'] as String).isNotEmpty
                  ? item['name'] as String
                  : AccessRequestDocument.nameFromUrl(item['url'] as String),
              storagePath: item['storagePath'] is String
                  ? item['storagePath'] as String
                  : '',
              size: item['size'] is num ? (item['size'] as num).toInt() : null,
              contentType: item['contentType'] is String
                  ? item['contentType'] as String
                  : null,
            ),
      ],
      status: data['status'] as String? ?? 'pendiente',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      rejectionReason: data['rejectionReason'] as String?,
    );
  }
}
