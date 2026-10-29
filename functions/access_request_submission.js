// Authentication and attachment validation for server-only access requests.
const {validStoredFileFormat} = require("./content_attachments");
const activeAccountConflictMessage = "No pudimos procesar tu solicitud porque algunos de los datos ingresados ya están asociados a una cuenta activa. Revisa la información o comunícate con un administrador.";
function createAccessRequestSubmission({identity, storage, HttpsError}) {
  return async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Inicia la solicitud nuevamente.");
    if (request.auth.token?.firebase?.sign_in_provider !== "anonymous") {
      throw new HttpsError("permission-denied", "Cierra sesión antes de enviar otra solicitud.");
    }
    const data = request.data || {};
    const allowed = ["requestId", "name", "dni", "phone", "email", "address", "timeLivingHere", "reason", "identityDocumentPath"];
    if (typeof data !== "object" || Array.isArray(data) ||
        Object.keys(data).length !== allowed.length ||
        Object.keys(data).some((key) => !allowed.includes(key) || typeof data[key] !== "string")) {
      throw new HttpsError("invalid-argument", "La solicitud contiene campos o tipos no permitidos.");
    }
    const documentPath = String(data.identityDocumentPath || "");
    const prefix = `access_requests/${uid}/identity/`;
    const filename = documentPath.slice(prefix.length);
    if (!documentPath.startsWith(prefix) || documentPath.length > 1024 ||
        !/^[A-Za-z0-9._-]{1,400}$/.test(filename) || [".", ".."].includes(filename)) {
      throw new HttpsError("invalid-argument", "El documento adjunto no corresponde a esta solicitud.");
    }
    let url;
    try {
      const file = storage().bucket().file(documentPath);
      const [metadata] = await file.getMetadata();
      const size = Number(metadata.size);
      if (!["image/jpeg", "image/png", "image/webp", "application/pdf"].includes(metadata.contentType) ||
          !Number.isFinite(size) || size <= 0 || size > 5 * 1024 * 1024 ||
          metadata.metadata?.uploadedBy !== uid) {
        throw new HttpsError("invalid-argument", "Adjunta un JPG, JPEG, PNG, WEBP o PDF válido de hasta 5 MB.");
      }
      const [header] = await file.download({start: 0, end: 15});
      if (!validStoredFileFormat(header, metadata.contentType, filename)) {
        throw new HttpsError("invalid-argument", "La extensión del archivo no coincide con su formato real.");
      }
      // The identity document is readable through authenticated Storage only.
      // Do not publish a shareable bearer token in an administrative record.
      await file.setMetadata({metadata: {...metadata.metadata, firebaseStorageDownloadTokens: null}});
      url = `gs://${file.bucket.name}/${documentPath}`;
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("failed-precondition", "No se pudo validar el documento adjunto. Vuelve a intentarlo.");
    }
    try {
      return await identity.submitAccessRequest(uid, {...data,
        identityDocumentPath: documentPath, identityDocumentUrl: url});
    } catch (error) {
      if (error.code === "already-exists" && error.details?.reason === "active-account-conflict") {
        throw new HttpsError("already-exists", activeAccountConflictMessage, {reason: "active-account-conflict"});
      }
      throw error;
    }
  };
}

module.exports = {createAccessRequestSubmission, activeAccountConflictMessage};
