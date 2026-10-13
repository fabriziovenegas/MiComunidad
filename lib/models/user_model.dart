import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/text_encoding.dart';

enum UserRole { vecino, admin }

class AppUser {
  final String userId;
  final String email;
  final String nombre;
  final UserRole role;
  final String approvalStatus; // "aprobado" | "pendiente" | "rechazado"
  final DateTime joinDate;
  final String? phone;
  final String dni;
  final String address;
  final String timeLivingHere;
  final String reason;
  final String communityId;
  final DateTime createdAt;
  final DateTime? updatedAt;

  AppUser({
    required this.userId,
    required this.email,
    required this.nombre,
    required this.role,
    required this.approvalStatus,
    required this.joinDate,
    this.phone,
    this.dni = '',
    this.address = '',
    this.timeLivingHere = '',
    this.reason = '',
    required this.communityId,
    required this.createdAt,
    this.updatedAt,
  });

  // Getters para verificar rol
  bool get isAdmin => role == UserRole.admin;
  bool get isNeighbor => role == UserRole.vecino;
  bool get isApproved => approvalStatus == "aprobado";
  bool get isPending => approvalStatus == "pendiente";
  bool get isRejected => approvalStatus == "rechazado";

  // Iniciales para avatar
  String get initials {
    final value = nombre
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return value.isEmpty ? '?' : value;
  }

  // Convertir a JSON para Firestore
  Map<String, dynamic> toJson() => {
        'userId': userId,
        'email': email,
        'nombre': nombre,
        'role': role.name,
        'approvalStatus': approvalStatus,
        'joinDate': joinDate,
        'phone': phone,
        'dni': dni,
        'address': address,
        'timeLivingHere': timeLivingHere,
        'reason': reason,
        'communityId': communityId,
        'createdAt': createdAt,
        'updatedAt': updatedAt ?? DateTime.now(),
      };

  // Crear desde Firestore
  factory AppUser.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw StateError('El perfil no contiene datos.');
    }
    final rawRole = data['role'] as String?;
    final role = switch (rawRole) {
      'admin' => UserRole.admin,
      'vecino' => UserRole.vecino,
      _ => throw StateError('El perfil contiene un rol no permitido.'),
    };
    return AppUser(
      userId: doc.id,
      email: readableText(data['email']),
      nombre: readableText(data['nombre']),
      role: role,
      approvalStatus: data['approvalStatus'] ?? 'pendiente',
      joinDate: (data['joinDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      phone: readableText(data['phone']),
      dni: readableText(data['dni']),
      address: readableText(data['address']),
      timeLivingHere: readableText(data['timeLivingHere']),
      reason: readableText(data['reason']),
      communityId: data['communityId'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  // Copiar con cambios
  AppUser copyWith({
    String? userId,
    String? email,
    String? nombre,
    UserRole? role,
    String? approvalStatus,
    DateTime? joinDate,
    String? phone,
    String? dni,
    String? address,
    String? timeLivingHere,
    String? reason,
    String? communityId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AppUser(
      userId: userId ?? this.userId,
      email: email ?? this.email,
      nombre: nombre ?? this.nombre,
      role: role ?? this.role,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      joinDate: joinDate ?? this.joinDate,
      phone: phone ?? this.phone,
      dni: dni ?? this.dni,
      address: address ?? this.address,
      timeLivingHere: timeLivingHere ?? this.timeLivingHere,
      reason: reason ?? this.reason,
      communityId: communityId ?? this.communityId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'AppUser(id: $userId, nombre: $nombre, role: ${role.name})';
}
