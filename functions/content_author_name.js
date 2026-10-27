// Read-only name projection. Never exposes or grants access to a user profile.
function createContentAuthorNameLookup({firestore: db, HttpsError}) {
  return async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
    const collection = request.data?.collection;
    const contentId = request.data?.contentId;
    if (!["projects", "events"].includes(collection) ||
        typeof contentId !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(contentId)) {
      throw new HttpsError("invalid-argument", "El contenido no es válido.");
    }
    const caller = await db.collection("users").doc(uid).get();
    const profile = caller.data();
    if (!caller.exists || profile.approvalStatus !== "aprobado" ||
        !["vecino", "admin"].includes(profile.role) ||
        profile.profileWithdrawalInProgress === true) {
      throw new HttpsError("permission-denied", "No tienes acceso a esta consulta.");
    }
    const content = await db.collection(collection).doc(contentId).get();
    const data = content.data();
    const visible = content.exists && (collection === "events" ||
      profile.role === "admin" || data.isTrashed === false);
    if (!visible) throw new HttpsError("permission-denied", "No tienes acceso a esta consulta.");

    // The creator comes from the authorized document, never the request payload.
    const authorId = data.createdBy;
    if (typeof authorId !== "string" || !authorId || authorId.includes("/") || authorId.length > 128) {
      return {name: null};
    }
    const author = authorId === uid ? caller : await db.collection("users").doc(authorId).get();
    const rawName = author.data()?.nombre;
    const name = typeof rawName === "string" ? rawName.trim() : "";
    return {name: name && name.length <= 160 ? name : null};
  };
}

module.exports = {createContentAuthorNameLookup};
