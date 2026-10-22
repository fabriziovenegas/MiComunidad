// Authentication and attachment validation for server-only access requests.
function createAccessRequestSubmission({identity, storage, getDownloadURL, HttpsError}) {
  return async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Inicia la solicitud nuevamente.");
    if (request.auth.token?.firebase?.sign_in_provider !== "anonymous") {
      throw new HttpsError("permission-denied", "Cierra sesión antes de enviar otra solicitud.");
    }
    const data = request.data || {};
    const documentPath = String(data.identityDocumentPath || "");
    const prefix = `access_requests/${uid}/identity/`;
    const filename = documentPath.slice(prefix.length);
    if (!documentPath.startsWith(prefix) || documentPath.length > 1024 ||
        !filename || filename.includes("/") || [".", ".."].includes(filename)) {
      throw new HttpsError("invalid-argument", "El documento adjunto no corresponde a esta solicitud.");
    }
    let url;
    try {
      const file = storage().bucket().file(documentPath);
      const [metadata] = await file.getMetadata();
      const size = Number(metadata.size);
      if (!["image/jpeg", "image/png", "application/pdf"].includes(metadata.contentType) ||
          !Number.isFinite(size) || size <= 0 || size > 5 * 1024 * 1024 ||
          metadata.metadata?.uploadedBy !== uid) {
        throw new HttpsError("invalid-argument", "Adjunta un JPG, PNG o PDF válido de hasta 5 MB.");
      }
      // Never trust a caller-provided download URL or a different Storage bucket.
      url = await getDownloadURL(file);
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("failed-precondition", "No se pudo validar el documento adjunto. Vuelve a intentarlo.");
    }
    return identity.submitAccessRequest(uid, {...data,
      identityDocumentPath: documentPath, identityDocumentUrl: url});
  };
}

module.exports = {createAccessRequestSubmission};
