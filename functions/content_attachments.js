function validStoredFileHeader(bytes, type) {
  if (!Buffer.isBuffer(bytes)) return false;
  if (type === "image/jpeg") return bytes.length >= 3 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255;
  if (type === "image/png") return bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
  if (type === "image/webp") return bytes.toString("ascii", 0, 4) === "RIFF" && bytes.toString("ascii", 8, 12) === "WEBP";
  return type === "application/pdf" && bytes.toString("ascii", 0, 5) === "%PDF-";
}

function storedFileTypeForName(name) {
  if (typeof name !== "string" || !name.includes(".")) return undefined;
  return {jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png", webp: "image/webp", pdf: "application/pdf"}[
    name.split(".").at(-1).toLowerCase()];
}

function validStoredFileFormat(bytes, type, name) {
  return storedFileTypeForName(name) === type && validStoredFileHeader(bytes, type);
}

function storedObjectPath(saved, bucketName) {
  if (typeof saved.storagePath === "string" && saved.storagePath) return saved.storagePath;
  try {
    const url = new URL(saved.url);
    if (url.protocol === "gs:" && url.hostname === bucketName) return decodeURIComponent(url.pathname.slice(1));
    const parts = url.pathname.split("/");
    if (url.origin !== "https://firebasestorage.googleapis.com" || parts.length !== 6 ||
        parts[1] !== "v0" || parts[2] !== "b" || parts[4] !== "o" ||
        decodeURIComponent(parts[3]) !== bucketName) return null;
    return decodeURIComponent(parts[5]);
  } catch (_) {
    return null;
  }
}

// Only the server may publish attachment records. Client URLs are never trusted.
function createContentAttachments({firestore: db, storage, HttpsError, FieldValue}) {
  const id = (value) => typeof value === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value);
  function payload(request, registration) {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
    const data = request.data;
    const keys = registration ? ["collection", "documentId", "kind", "attachmentId", "storagePath", "name"] :
      ["collection", "documentId", "kind", "attachmentId"];
    if (!data || typeof data !== "object" || Array.isArray(data) ||
        Object.keys(data).length !== keys.length || Object.keys(data).some((key) => !keys.includes(key)) ||
        !["projects", "reports", "events"].includes(data.collection) || !id(data.documentId) ||
        !id(data.attachmentId) || !["photos", ...(["events", "projects"].includes(data.collection) ? ["minutes"] : [])].includes(data.kind)) {
      throw new HttpsError("invalid-argument", "El adjunto no es válido.");
    }
    return data;
  }
  function belongs(path, data) {
    const prefix = `${data.collection}/${data.documentId}/${data.kind}/`;
    return typeof path === "string" && path.startsWith(prefix) && path.length <= 800 &&
      /^[A-Za-z0-9._-]{1,400}$/.test(path.slice(prefix.length)) &&
      ![".", ".."].includes(path.slice(prefix.length));
  }
  function approved(profile) {
    return profile?.approvalStatus === "aprobado" && ["vecino", "admin"].includes(profile.role) &&
      profile.profileWithdrawalInProgress !== true;
  }
  function contributions(data, parent, uid) {
    if (!parent || parent.deletionInProgress === true) return false;
    if (data.collection === "projects") return parent.isTrashed === false;
    if (data.collection === "events") return true;
    return (parent.moderationStatus === "aprobado" && ["pendiente", "en_revision", "en_proceso"].includes(parent.status)) ||
      (parent.moderationStatus === "pendiente" && parent.createdBy === uid &&
        ["pendiente", "en_revision", "en_proceso"].includes(parent.status));
  }
  async function records(data, uid, transaction) {
    const read = (reference) => transaction ? transaction.get(reference) : reference.get();
    const profile = await read(db.collection("users").doc(uid));
    if (!profile.exists || !approved(profile.data())) {
      throw new HttpsError("permission-denied", "Tu cuenta no tiene acceso a los adjuntos.");
    }
    const parent = await read(db.collection(data.collection).doc(data.documentId));
    if (!parent.exists) throw new HttpsError("not-found", "El contenido ya no existe.");
    return {profile: profile.data(), parent: parent.data()};
  }
  async function register(request) {
    const data = payload(request, true); const uid = request.auth.uid;
    if (!belongs(data.storagePath, data) ||
        !data.storagePath.split("/").at(-1).startsWith(`${data.attachmentId}_`) ||
        typeof data.name !== "string" || !data.name.trim() || data.name.length > 255 ||
        /[/\\]/.test(data.name) || Array.from(data.name).some((char) => char.charCodeAt(0) < 32)) {
      throw new HttpsError("invalid-argument", "El archivo no pertenece a este contenido.");
    }
    const before = await records(data, uid);
    if (!contributions(data, before.parent, uid)) {
      throw new HttpsError("permission-denied", "Este contenido ya no admite archivos.");
    }
    const file = storage().bucket().file(data.storagePath);
    let metadata;
    try {
      [metadata] = await file.getMetadata();
    } catch (_) {
      throw new HttpsError("failed-precondition", "El archivo aún no está disponible. Reintenta el envío.");
    }
    const type = storedFileTypeForName(data.name);
    const size = Number(metadata.size);
    const upload = metadata.metadata || {};
    const uploadId = upload.attachmentUploadId || upload.reportUploadId;
    if (!type || type !== metadata.contentType || (data.kind === "photos" && type === "application/pdf") ||
        !Number.isFinite(size) || size <= 0 || size > (data.kind === "minutes" ? 5 : 10) * 1024 * 1024 ||
        upload.uploadedBy !== uid || uploadId !== data.attachmentId ||
        (upload.attachmentUploadId && upload.reportUploadId)) {
      throw new HttpsError("invalid-argument", "El tipo, tamaño o propietario del archivo no es válido.");
    }
    const [header] = await file.download({start: 0, end: 15});
    if (!validStoredFileFormat(header, type, data.name) || storedFileTypeForName(data.storagePath) !== type) {
      throw new HttpsError("invalid-argument", "La extensión del archivo no coincide con su formato real.");
    }
    // New metadata contains no bearer download token. The client must use its
    // authenticated Storage SDK to read the object. Revoke its upload token.
    await file.setMetadata({metadata: {...metadata.metadata, firebaseStorageDownloadTokens: null}});
    const url = `gs://${file.bucket.name}/${data.storagePath}`;
    const reference = db.collection(data.collection).doc(data.documentId).collection(data.kind).doc(data.attachmentId);
    await db.runTransaction(async (transaction) => {
      const current = await records(data, uid, transaction);
      const previous = await transaction.get(reference);
      if (!contributions(data, current.parent, uid)) {
        throw new HttpsError("permission-denied", "Este contenido ya no admite archivos.");
      }
      if (previous.exists) {
        const stored = previous.data();
        if (stored.uploadedBy !== uid || stored.storagePath !== data.storagePath) {
          throw new HttpsError("already-exists", "Este adjunto pertenece a otro envío.");
        }
        return;
      }
      transaction.set(reference, {url, storagePath: data.storagePath, name: data.name,
        contentType: type === "application/pdf" ? type : "image", uploadedBy: uid,
        uploadId: data.attachmentId, createdAt: FieldValue.serverTimestamp()});
    });
    return {success: true};
  }
  async function remove(request) {
    const data = payload(request, false); const uid = request.auth.uid;
    const current = await records(data, uid);
    const reference = db.collection(data.collection).doc(data.documentId).collection(data.kind).doc(data.attachmentId);
    const snapshot = await reference.get();
    if (!snapshot.exists) return {success: true};
    const saved = snapshot.data();
    if (current.profile.role !== "admin" && (saved.uploadedBy !== uid || !contributions(data, current.parent, uid))) {
      throw new HttpsError("permission-denied", "No puedes eliminar este archivo.");
    }
    // A legacy poisoned document must not turn an admin click into deletion of
    // an unrelated object, even though the Admin SDK bypasses Storage Rules.
    const bucket = storage().bucket();
    const objectPath = storedObjectPath(saved, bucket.name);
    if (!belongs(objectPath, data)) {
      throw new HttpsError("failed-precondition", "La ruta del archivo requiere revisión. No se eliminó ningún archivo.");
    }
    const file = bucket.file(objectPath);
    try {
      const [metadata] = await file.getMetadata();
      if (current.profile.role !== "admin" && metadata.metadata?.uploadedBy !== uid) {
        throw new HttpsError("permission-denied", "Este archivo no te pertenece.");
      }
      await bucket.file(objectPath, {generation: metadata.generation}).delete();
    } catch (error) {
      if (error.code !== 404) throw error;
    }
    // Recheck membership/ownership and the unchanged target before removing the
    // record. Parent deletion or role revocation can never target another path.
    await db.runTransaction(async (transaction) => {
      const latest = await records(data, uid, transaction);
      const document = await transaction.get(reference);
      if (!document.exists) return;
      if (document.data().storagePath !== saved.storagePath || document.data().url !== saved.url ||
          (latest.profile.role !== "admin" && (document.data().uploadedBy !== uid || !contributions(data, latest.parent, uid)))) {
        throw new HttpsError("permission-denied", "No puedes eliminar este archivo.");
      }
      transaction.delete(reference);
    });
    return {success: true};
  }
  return {register, remove};
}

module.exports = {createContentAttachments, validStoredFileHeader, validStoredFileFormat, storedFileTypeForName, storedObjectPath};
