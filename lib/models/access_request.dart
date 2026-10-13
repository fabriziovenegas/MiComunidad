import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/text_encoding.dart';

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
      status: data['status'] as String? ?? 'pendiente',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      rejectionReason: data['rejectionReason'] as String?,
    );
  }
}
