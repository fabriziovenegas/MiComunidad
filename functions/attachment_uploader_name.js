// Exposes only the current uploader name after checking access to the attachment.
function createAttachmentUploaderNameLookup({firestore: db, HttpsError}) {
  return async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
    const input = request.data;
    const keys = ["collection", "documentId", "kind", "attachmentId"];
    const id = (v) => typeof v === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(v);
    if (!input || typeof input !== "object" || Array.isArray(input) ||
        Object.keys(input).length !== keys.length || Object.keys(input).some((k) => !keys.includes(k)) ||
        !["projects", "events", "reports"].includes(input.collection) ||
        !id(input.documentId) || !id(input.attachmentId) ||
        !["photos", ...(input.collection === "reports" ? [] : ["minutes"])].includes(input.kind)) {
      throw new HttpsError("invalid-argument", "El adjunto no es válido.");
    }
    const viewer = await db.doc(`users/${uid}`).get();
    const p = viewer.data();
    if (!viewer.exists || p.approvalStatus !== "aprobado" ||
        !["admin", "vecino"].includes(p.role) || p.profileWithdrawalInProgress === true) {
      throw new HttpsError("permission-denied", "No tienes acceso.");
    }
    const parent = await db.doc(`${input.collection}/${input.documentId}`).get();
    const data = parent.data();
    const visible = parent.exists && (p.role === "admin" || input.collection === "events" ||
      (input.collection === "projects" && data.isTrashed === false) ||
      (input.collection === "reports" && (data.createdBy === uid ||
        (data.moderationStatus === "aprobado" && ["pendiente", "en_revision", "en_proceso", "resuelto"].includes(data.status)))));
    if (!visible) throw new HttpsError("permission-denied", "No tienes acceso.");
    const attachment = await db.doc(`${input.collection}/${input.documentId}/${input.kind}/${input.attachmentId}`).get();
    if (!attachment.exists) throw new HttpsError("not-found", "El adjunto no existe.");
    const uploader = attachment.data().uploadedBy;
    if (!id(uploader)) return {name: null};
    const author = uploader === uid ? viewer : await db.doc(`users/${uploader}`).get();
    const name = author.data()?.nombre;
    return {name: typeof name === "string" && name.trim() && name.trim().length <= 160 ? name.trim() : null};
  };
}
module.exports = {createAttachmentUploaderNameLookup};
