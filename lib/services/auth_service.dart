import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import '../models/user_model.dart';
import 'file_service.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final firebase.FirebaseAuth _auth = firebase.FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'southamerica-east1');

  Stream<firebase.User?> get authStateChanges => _auth.authStateChanges();
  firebase.User? get currentUser => _auth.currentUser;

  Future<AppUser?> currentProfile() async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return null;
    final document = await _db.collection('users').doc(user.uid).get();
    if (!document.exists) return null;
    return AppUser.fromFirestore(document);
  }

  Stream<AppUser?> profileStream(String userId) =>
      _db.collection('users').doc(userId).snapshots().map((document) =>
          document.exists ? AppUser.fromFirestore(document) : null);

  Future<void> signIn({required String email, required String password}) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final document =
        await _db.collection('users').doc(credential.user!.uid).get();
    if (!document.exists) {
      await _auth.signOut();
      throw const AuthFlowException('La cuenta no tiene un perfil habilitado.');
    }
    final data = document.data()!;
    final role = data['role'];
    final approval = data['approvalStatus'];
    if (role != 'vecino' && role != 'admin') {
      await _auth.signOut();
      throw const AuthFlowException('El perfil tiene un rol no permitido.');
    }
    if (approval != 'aprobado') {
      await _auth.signOut();
      throw AuthFlowException(
        approval == 'rechazado'
            ? 'La solicitud de acceso fue rechazada.'
            : 'La solicitud todavía está en revisión.',
      );
    }
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.setLanguageCode('es');
    await _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
  }

  Future<void> requestPasswordResetCode(String email) async {
    try {
      await _functions.httpsCallable('requestPasswordResetCode').call({
        'email': email.trim().toLowerCase(),
      });
    } on FirebaseFunctionsException catch (error) {
      throw _functionsError(error);
    }
  }

  Future<void> confirmPasswordResetCode({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    try {
      await _functions.httpsCallable('confirmPasswordResetCode').call({
        'email': email.trim().toLowerCase(),
        'code': code.trim(),
        'newPassword': newPassword,
      });
    } on FirebaseFunctionsException catch (error) {
      throw _functionsError(error);
    }
  }

  Future<String> submitAccessRequest({
    required String name,
    required String dni,
    required String phone,
    required String email,
    required String address,
    required String timeLivingHere,
    required String reason,
    required SelectedUpload identityDocument,
  }) async {
    Map<String, dynamic>? existingRequest;
    try {
      existingRequest = await _fetchRequestStatus(dni);
    } on FirebaseFunctionsException catch (error) {
      // Permite registrar la primera solicitud durante un despliegue incompleto
      // del backend. La regla de duplicados vuelve a aplicarse en cuanto la
      // función consultable está disponible.
      if (error.code != 'not-found') {
        throw _functionsError(error);
      }
    }
    final existingStatus = existingRequest?['status'];
    if (existingStatus == 'pendiente' || existingStatus == 'aprobado') {
      throw const AuthFlowException(
        'Ya existe una solicitud activa para este DNI. Consulta su estado.',
      );
    }
    try {
      final current = _auth.currentUser;
      if (current != null && !current.isAnonymous) {
        throw const AuthFlowException(
            'Cierra sesión antes de enviar otra solicitud.');
      }
      final anonymous = current ?? (await _auth.signInAnonymously()).user!;
      final uploaded = await FileService.upload(
        selected: identityDocument,
        folder: 'access_requests/${anonymous.uid}/identity',
        uploadedBy: anonymous.uid,
      );
      final document = _db.collection('accessRequests').doc();
      final result = await _functions
          .httpsCallable('submitAccessRequest')
          .call<Map<String, dynamic>>({
        'requestId': document.id,
        'name': name.trim(),
        'dni': dni.trim(),
        'phone': phone.trim(),
        'email': email.trim().toLowerCase(),
        'address': address.trim(),
        'timeLivingHere': timeLivingHere,
        'reason': reason.trim(),
        'identityDocumentPath': uploaded.storagePath,
      });
      if (result.data['requestId'] != document.id) {
        throw const AuthFlowException(
            'No pudimos confirmar la solicitud. Consulta su estado antes de reenviarla.');
      }
      await _auth.signOut();
      return document.id;
    } on FirebaseFunctionsException catch (error) {
      throw _functionsError(error);
    } on firebase.FirebaseAuthException catch (error) {
      throw _authError(error);
    } on FirebaseException catch (error) {
      throw _firebaseError(error);
    }
  }

  Future<Map<String, dynamic>?> findRequestStatus(String dni) async {
    try {
      return await _fetchRequestStatus(dni);
    } on FirebaseFunctionsException catch (error) {
      throw _functionsError(error);
    }
  }

  Future<Map<String, dynamic>?> _fetchRequestStatus(String dni) async {
    final result = await _functions
        .httpsCallable('getAccessRequestStatus')
        .call<Map<String, dynamic>>({'dni': dni.trim()});
    return result.data['request'] as Map<String, dynamic>?;
  }

  AuthFlowException _functionsError(FirebaseFunctionsException error) {
    return switch (error.code) {
      'invalid-argument' => AuthFlowException(error.message ??
          'Revisa los datos ingresados e inténtalo nuevamente.'),
      'already-exists' || 'failed-precondition' => AuthFlowException(
          error.message ?? 'La solicitud no puede procesarse en este momento.'),
      'permission-denied' ||
      'unauthenticated' =>
        const AuthFlowException('No tienes permiso para realizar esta acción.'),
      'not-found' => const AuthFlowException(
          'El servicio de solicitudes se está habilitando. Inténtalo nuevamente en unos minutos.'),
      'unavailable' || 'deadline-exceeded' => const AuthFlowException(
          'No pudimos conectar con el servicio. Revisa tu conexión e inténtalo nuevamente.'),
      _ => const AuthFlowException(
          'No pudimos procesar la solicitud. Inténtalo nuevamente.'),
    };
  }

  AuthFlowException _authError(firebase.FirebaseAuthException error) {
    return switch (error.code) {
      'network-request-failed' => const AuthFlowException(
          'No pudimos conectar con el servicio. Revisa tu conexión e inténtalo nuevamente.'),
      'operation-not-allowed' => const AuthFlowException(
          'El registro de solicitudes todavía no está habilitado. Comunícate con la administración.'),
      _ => const AuthFlowException(
          'No pudimos validar el envío. Inténtalo nuevamente.'),
    };
  }

  AuthFlowException _firebaseError(FirebaseException error) {
    return switch (error.code) {
      'unauthorized' || 'permission-denied' => const AuthFlowException(
          'No fue posible guardar la solicitud. Comunícate con la administración.'),
      'retry-limit-exceeded' || 'unavailable' => const AuthFlowException(
          'La conexión se interrumpió. Inténtalo nuevamente.'),
      _ => const AuthFlowException(
          'No pudimos guardar la solicitud. Inténtalo nuevamente.'),
    };
  }
}

class AuthFlowException implements Exception {
  const AuthFlowException(this.message);
  final String message;
  @override
  String toString() => message;
}
