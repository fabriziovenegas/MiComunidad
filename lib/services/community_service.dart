import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/access_request.dart';
import '../models/user_model.dart';
import '../models/report_edit.dart';
import 'file_service.dart';
import 'pending_upload_service.dart';
import 'report_content_editor.dart';
import 'report_comment_writer.dart';
import 'report_deletion_guard.dart';

class PublicCommunitySummary {
  const PublicCommunitySummary({
    required this.activeMembers,
    required this.projects,
  });

  final int activeMembers;
  final int projects;
}

class ProjectDeletionException implements Exception {
  const ProjectDeletionException({
    required this.failedStep,
    required this.completedSteps,
    required this.cause,
  });

  final String failedStep;
  final List<String> completedSteps;
  final Object cause;

  String get userMessage {
    final completed = completedSteps.isEmpty
        ? 'No se completó ningún paso de eliminación.'
        : 'Ya se completó: ${completedSteps.join(', ')}.';
    return 'No se pudo eliminar el proyecto. Falló el paso: $failedStep. '
        '$completed El documento principal se conservó. Error: $cause';
  }

  @override
  String toString() => userMessage;
}

class ReportDeletionException implements Exception {
  const ReportDeletionException({
    required this.failedStep,
    required this.completedSteps,
    required this.cause,
  });

  final String failedStep;
  final List<String> completedSteps;
  final Object cause;

  String get userMessage {
    final completed = completedSteps.isEmpty
        ? 'No se completó ningún paso de eliminación.'
        : 'Ya se completó: ${completedSteps.join(', ')}.';
    return 'No se pudo eliminar el reporte. Falló el paso: $failedStep. '
        '$completed El documento principal se conservó. '
        '${completedSteps.contains('bloqueo de nuevas aportaciones') ? 'Las nuevas aportaciones permanecen bloqueadas hasta reintentar la eliminación. ' : ''}'
        'Error: $cause';
  }

  @override
  String toString() => userMessage;
}

class CommunityService {
  CommunityService._();
  static final CommunityService instance = CommunityService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'southamerica-east1');
  final Set<String> _projectsBeingDeleted = <String>{};
  final Set<String> _reportsBeingDeleted = <String>{};

  Future<String?> currentReportAuthorName(String reportId) async {
    final result = await _functions
        .httpsCallable('getReportAuthorName',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 10)))
        .call<Map<String, dynamic>>({'reportId': reportId});
    final name = result.data['name'];
    return name is String && name.trim().isNotEmpty ? name.trim() : null;
  }

  Future<PublicCommunitySummary> publicSummary() async {
    final result = await _functions
        .httpsCallable('getPublicCommunitySummary')
        .call<Map<String, dynamic>>();
    final data = result.data;
    return PublicCommunitySummary(
      activeMembers: (data['activeMembers'] as num?)?.toInt() ?? 0,
      projects: (data['projects'] as num?)?.toInt() ?? 0,
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> activeProjects() => _db
      .collection('projects')
      .where('isTrashed', isEqualTo: false)
      .snapshots();
  Stream<QuerySnapshot<Map<String, dynamic>>> archivedProjects() => _db
      .collection('projects')
      .where('isTrashed', isEqualTo: true)
      .snapshots();
  Stream<QuerySnapshot<Map<String, dynamic>>> approvedReports() => _db
          .collection('reports')
          .where('moderationStatus', isEqualTo: 'aprobado')
          .where(
        'status',
        whereIn: ['pendiente', 'en_revision', 'en_proceso', 'resuelto'],
      ).snapshots();
  Stream<QuerySnapshot<Map<String, dynamic>>> pendingReports() => _db
      .collection('reports')
      .orderBy('createdAt', descending: true)
      .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> ownReports(String userId) => _db
      .collection('reports')
      .where('createdBy', isEqualTo: userId)
      .snapshots();

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      reportsVisibleToNeighbor({
    required String userId,
    required bool includeOwnReports,
  }) {
    final approved = approvedReports();
    if (!includeOwnReports) {
      return approved.map((snapshot) => _sortReports(snapshot.docs));
    }

    return Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>.multi(
      (controller) {
        QuerySnapshot<Map<String, dynamic>>? approvedSnapshot;
        QuerySnapshot<Map<String, dynamic>>? ownSnapshot;

        void emitVisibleReports() {
          if (approvedSnapshot == null || ownSnapshot == null) return;

          final documents =
              <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
            for (final document in approvedSnapshot!.docs)
              document.id: document,
            for (final document in ownSnapshot!.docs) document.id: document,
          }.values.toList();
          controller.add(_sortReports(documents));
        }

        final approvedSubscription = approved.listen(
          (snapshot) {
            approvedSnapshot = snapshot;
            emitVisibleReports();
          },
          onError: controller.addError,
        );
        final ownSubscription = ownReports(userId).listen(
          (snapshot) {
            ownSnapshot = snapshot;
            emitVisibleReports();
          },
          onError: controller.addError,
        );

        controller.onCancel = () async {
          await approvedSubscription.cancel();
          await ownSubscription.cancel();
        };
      },
    );
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortReports(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
  ) {
    final sorted = documents.toList();
    sorted.sort((left, right) {
      final leftDate = left.data()['createdAt'] as Timestamp?;
      final rightDate = right.data()['createdAt'] as Timestamp?;
      return (rightDate?.millisecondsSinceEpoch ?? 0)
          .compareTo(leftDate?.millisecondsSinceEpoch ?? 0);
    });
    return sorted;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> events() =>
      _db.collection('events').orderBy('eventDate').snapshots();
  Stream<List<AccessRequest>> accessRequests() => _db
      .collection('accessRequests')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snapshot) =>
          snapshot.docs.map(AccessRequest.fromFirestore).toList());
  Stream<List<AppUser>> neighbors() => _db
      .collection('users')
      .where('role', isEqualTo: 'vecino')
      .snapshots()
      .map((snapshot) => snapshot.docs.map(AppUser.fromFirestore).toList());
  Stream<List<AppUser>> members() => _db
      .collection('users')
      .where('approvalStatus', isEqualTo: 'aprobado')
      .snapshots()
      .map((snapshot) => snapshot.docs.map(AppUser.fromFirestore).toList());

  Future<void> createProject(Map<String, dynamic> data) =>
      _db.collection('projects').add({
        ...data,
        'isTrashed': false,
        'createdBy': FirebaseAuth.instance.currentUser!.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> updateProject(String id, Map<String, dynamic> data) =>
      _db.collection('projects').doc(id).update({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> moveProjectToTrash(String projectId) async {
    await updateProject(projectId, {
      'isTrashed': true,
      'trashedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> restoreProject(String projectId) async {
    await updateProject(projectId, {
      'isTrashed': false,
      'trashedAt': FieldValue.delete(),
    });
  }

  Future<void> permanentlyDeleteArchivedProject(String projectId) async {
    if (!_projectsBeingDeleted.add(projectId)) {
      throw const ProjectDeletionException(
        failedStep: 'iniciar la eliminación',
        completedSteps: [],
        cause: 'Ya hay una eliminación en curso para este proyecto.',
      );
    }

    final completedSteps = <String>[];
    final projectReference = _db.collection('projects').doc(projectId);

    try {
      final project = await projectReference.get();
      if (!project.exists) {
        throw const ProjectDeletionException(
          failedStep: 'verificar el proyecto',
          completedSteps: [],
          cause: 'El proyecto ya no existe.',
        );
      }
      if (project.data()?['isTrashed'] != true) {
        throw const ProjectDeletionException(
          failedStep: 'verificar el proyecto',
          completedSteps: [],
          cause: 'El proyecto no está archivado.',
        );
      }

      var deletedStorageFiles = 0;
      try {
        final paths = await FileService.listFilesRecursively(
          'projects/$projectId/photos',
        );
        for (final path in paths) {
          await FileService.delete(storagePath: path);
          deletedStorageFiles++;
        }
        completedSteps.add(
          'archivos de Storage ($deletedStorageFiles)',
        );
      } catch (error) {
        throw ProjectDeletionException(
          failedStep: 'eliminar los archivos de Storage',
          completedSteps: [
            if (deletedStorageFiles > 0)
              'archivos de Storage eliminados parcialmente ($deletedStorageFiles)',
          ],
          cause: error,
        );
      }

      final deletedPhotoDocuments = await _deleteProjectSubcollection(
        collection: projectReference.collection('photos'),
        description: 'eliminar los metadatos de fotografías',
        completedSteps: completedSteps,
      );
      completedSteps.add(
        'metadatos de fotografías ($deletedPhotoDocuments)',
      );

      final deletedCommentDocuments = await _deleteProjectSubcollection(
        collection: projectReference.collection('comments'),
        description: 'eliminar los comentarios',
        completedSteps: completedSteps,
      );
      completedSteps.add('comentarios ($deletedCommentDocuments)');

      try {
        await projectReference.delete();
      } catch (error) {
        throw ProjectDeletionException(
          failedStep: 'eliminar el documento principal',
          completedSteps: List.unmodifiable(completedSteps),
          cause: error,
        );
      }
    } on ProjectDeletionException {
      rethrow;
    } catch (error) {
      throw ProjectDeletionException(
        failedStep: 'verificar el proyecto',
        completedSteps: List.unmodifiable(completedSteps),
        cause: error,
      );
    } finally {
      _projectsBeingDeleted.remove(projectId);
    }
  }

  Future<int> _deleteProjectSubcollection({
    required CollectionReference<Map<String, dynamic>> collection,
    required String description,
    required List<String> completedSteps,
  }) async {
    const batchSize = 400;
    var deletedDocuments = 0;

    try {
      while (true) {
        final snapshot = await collection.limit(batchSize).get();
        if (snapshot.docs.isEmpty) return deletedDocuments;

        final batch = _db.batch();
        for (final document in snapshot.docs) {
          batch.delete(document.reference);
        }
        await batch.commit();
        deletedDocuments += snapshot.docs.length;
      }
    } catch (error) {
      throw ProjectDeletionException(
        failedStep: description,
        completedSteps: [
          ...completedSteps,
          if (deletedDocuments > 0)
            '$description parcialmente ($deletedDocuments documentos)',
        ],
        cause: error,
      );
    }
  }

  Future<void> createReport(Map<String, dynamic> data) =>
      _db.collection('reports').add({
        ...data,
        'createdBy': FirebaseAuth.instance.currentUser!.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'status': 'pendiente',
        'moderationStatus': 'pendiente',
      });

  Future<void> updateReport(String id, Map<String, dynamic> data) =>
      _db.collection('reports').doc(id).update({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> updateOwnReportContent(String id, ReportEditDraft draft) =>
      ReportContentEditor(
        firestore: _db,
        currentUserId: () {
          final user = FirebaseAuth.instance.currentUser;
          return user == null || user.isAnonymous ? null : user.uid;
        },
      ).save(id, draft);

  Future<void> permanentlyDeleteCompletedReport(String reportId) async {
    if (!_reportsBeingDeleted.add(reportId)) {
      throw const ReportDeletionException(
        failedStep: 'iniciar la eliminación',
        completedSteps: [],
        cause: 'Ya hay una eliminación en curso para este reporte.',
      );
    }

    final completedSteps = <String>[];
    final reportReference = _db.collection('reports').doc(reportId);

    try {
      final authenticatedUser = FirebaseAuth.instance.currentUser;
      if (authenticatedUser == null) {
        throw const ReportDeletionException(
          failedStep: 'verificar al administrador',
          completedSteps: [],
          cause: 'No hay un usuario autenticado.',
        );
      }

      final profile =
          await _db.collection('users').doc(authenticatedUser.uid).get();
      final profileData = profile.data();
      if (!profile.exists ||
          profileData?['role'] != 'admin' ||
          profileData?['approvalStatus'] != 'aprobado') {
        throw const ReportDeletionException(
          failedStep: 'verificar al administrador',
          completedSteps: [],
          cause: 'Solo un administrador aprobado puede eliminar reportes.',
        );
      }

      final report = await reportReference.get();
      if (!report.exists) {
        throw const ReportDeletionException(
          failedStep: 'verificar el reporte',
          completedSteps: [],
          cause: 'El reporte ya no existe.',
        );
      }

      final data = report.data()!;
      final moderationStatus = data['moderationStatus'];
      final operationalStatus = data['status'];
      final resolved =
          moderationStatus == 'aprobado' && operationalStatus == 'resuelto';
      final rejected = moderationStatus == 'rechazado' ||
          (moderationStatus == 'aprobado' && operationalStatus == 'rechazado');
      if (!resolved && !rejected) {
        throw const ReportDeletionException(
          failedStep: 'verificar el estado del reporte',
          completedSteps: [],
          cause: 'Solo se pueden eliminar reportes resueltos o rechazados.',
        );
      }

      try {
        await ReportDeletionGuard(
          firestore: _db,
          currentUserId: () => FirebaseAuth.instance.currentUser?.uid,
        ).begin(reportId);
        completedSteps.add('bloqueo de nuevas aportaciones');
      } catch (error) {
        throw ReportDeletionException(
          failedStep: 'bloquear nuevas aportaciones antes de eliminar',
          completedSteps: [],
          cause: error,
        );
      }

      var deletedStorageFiles = 0;
      try {
        final paths = await FileService.listFilesRecursively(
          'reports/$reportId/photos',
        );
        for (final path in paths) {
          await FileService.delete(storagePath: path);
          deletedStorageFiles++;
        }
        completedSteps.add('archivos de Storage ($deletedStorageFiles)');
      } catch (error) {
        throw ReportDeletionException(
          failedStep: 'eliminar los archivos de Storage',
          completedSteps: [
            ...completedSteps,
            if (deletedStorageFiles > 0)
              'archivos de Storage eliminados parcialmente ($deletedStorageFiles)',
          ],
          cause: error,
        );
      }

      final deletedPhotoDocuments = await _deleteReportSubcollection(
        collection: reportReference.collection('photos'),
        description: 'eliminar los metadatos de fotografías',
        completedSteps: completedSteps,
      );
      completedSteps.add(
        'metadatos de fotografías ($deletedPhotoDocuments)',
      );

      final deletedCommentDocuments = await _deleteReportSubcollection(
        collection: reportReference.collection('comments'),
        description: 'eliminar los comentarios',
        completedSteps: completedSteps,
      );
      completedSteps.add('comentarios ($deletedCommentDocuments)');

      try {
        await reportReference.delete();
      } catch (error) {
        throw ReportDeletionException(
          failedStep: 'eliminar el documento principal',
          completedSteps: List.unmodifiable(completedSteps),
          cause: error,
        );
      }
    } on ReportDeletionException {
      rethrow;
    } catch (error) {
      throw ReportDeletionException(
        failedStep: 'verificar el reporte',
        completedSteps: List.unmodifiable(completedSteps),
        cause: error,
      );
    } finally {
      _reportsBeingDeleted.remove(reportId);
    }
  }

  Future<int> _deleteReportSubcollection({
    required CollectionReference<Map<String, dynamic>> collection,
    required String description,
    required List<String> completedSteps,
  }) async {
    const batchSize = 400;
    var deletedDocuments = 0;

    try {
      while (true) {
        final snapshot = await collection.limit(batchSize).get();
        if (snapshot.docs.isEmpty) return deletedDocuments;

        final batch = _db.batch();
        for (final document in snapshot.docs) {
          batch.delete(document.reference);
        }
        await batch.commit();
        deletedDocuments += snapshot.docs.length;
      }
    } catch (error) {
      throw ReportDeletionException(
        failedStep: description,
        completedSteps: [
          ...completedSteps,
          if (deletedDocuments > 0)
            '$description parcialmente ($deletedDocuments documentos)',
        ],
        cause: error,
      );
    }
  }

  Future<void> createEvent(Map<String, dynamic> data) =>
      _db.collection('events').add({
        ...data,
        'createdBy': FirebaseAuth.instance.currentUser!.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
  Future<void> deleteEvent(String eventId) async {
    await _db.collection('events').doc(eventId).delete();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> comments(
    String collection,
    String documentId,
  ) =>
      _db
          .collection(collection)
          .doc(documentId)
          .collection('comments')
          .orderBy('createdAt')
          .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> attachments(
    String collection,
    String documentId,
    String kind,
  ) =>
      _db
          .collection(collection)
          .doc(documentId)
          .collection(kind)
          .orderBy('createdAt', descending: true)
          .snapshots();

  Future<void> addComment({
    required String collection,
    required String documentId,
    required String text,
    required String authorName,
  }) async {
    if (collection == 'reports') {
      await ReportCommentWriter(
        firestore: _db,
        currentUserId: () {
          final user = FirebaseAuth.instance.currentUser;
          return user == null || user.isAnonymous ? null : user.uid;
        },
      ).add(reportId: documentId, text: text, authorName: authorName);
      return;
    }
    await _db
        .collection(collection)
        .doc(documentId)
        .collection('comments')
        .add({
      'text': text.trim(),
      'authorId': FirebaseAuth.instance.currentUser!.uid,
      'authorName': authorName,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> addAttachment({
    required String collection,
    required String documentId,
    required String kind,
    required SelectedUpload selected,
  }) =>
      PendingUploadService.instance.uploadOrQueue(
        collection: collection,
        documentId: documentId,
        kind: kind,
        selected: selected,
      );

  Future<void> deleteComment({
    required String collection,
    required String documentId,
    required String commentId,
  }) =>
      _db
          .collection(collection)
          .doc(documentId)
          .collection('comments')
          .doc(commentId)
          .delete();

  Future<void> deleteAttachment({
    required String collection,
    required String documentId,
    required String kind,
    required String attachmentId,
    String? storagePath,
    String? downloadUrl,
  }) async {
    await FileService.delete(
      storagePath: storagePath,
      downloadUrl: downloadUrl,
    );
    await _db
        .collection(collection)
        .doc(documentId)
        .collection(kind)
        .doc(attachmentId)
        .delete();
  }

  Future<void> moderateReport({
    required String reportId,
    required bool approve,
    String? reason,
  }) =>
      updateReport(reportId, {
        'moderationStatus': approve ? 'aprobado' : 'rechazado',
        'moderationReason': reason?.trim(),
        'moderatedBy': FirebaseAuth.instance.currentUser!.uid,
        'moderatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> setUserRole(String userId, UserRole role) async {
    await _functions.httpsCallable('setUserRole').call({
      'userId': userId,
      'role': role.name,
    });
  }

  Future<void> updateOwnProfile({
    required String nombre,
    required String dni,
    required String phone,
    required String email,
    required String address,
    required String timeLivingHere,
    required String reason,
  }) async {
    await _functions.httpsCallable('updateOwnProfile').call({
      'nombre': nombre.trim(),
      'dni': dni.trim(),
      'phone': phone.trim(),
      'email': email.trim().toLowerCase(),
      'address': address.trim(),
      'timeLivingHere': timeLivingHere.trim(),
      'reason': reason.trim(),
    });
  }

  Future<void> reviewAccessRequest({
    required String requestId,
    required bool approve,
    String? reason,
  }) async {
    await _functions.httpsCallable('reviewAccessRequest').call({
      'requestId': requestId,
      'action': approve ? 'approve' : 'reject',
      'reason': reason?.trim(),
    });
  }

  Future<void> deleteAccessRequest(String requestId) async {
    await _db.collection('accessRequests').doc(requestId).delete();
  }

  Future<void> removeNeighbor(String userId) async {
    await _functions.httpsCallable('removeNeighbor').call({'userId': userId});
  }
}
