// Read-only lookup: report visibility is checked before reading its author's name.
function createReportAuthorNameLookup({firestore: db, HttpsError}) {
  return async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
    const reportId = request.data?.reportId;
    if (typeof reportId !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(reportId)) {
      throw new HttpsError("invalid-argument", "El reporte no es válido.");
    }

    const caller = await db.collection("users").doc(uid).get();
    const profile = caller.data();
    if (!caller.exists || profile.approvalStatus !== "aprobado" ||
        !["vecino", "admin"].includes(profile.role) || profile.profileWithdrawalInProgress === true) {
      throw new HttpsError("permission-denied", "No tienes acceso a esta consulta.");
    }
    const report = await db.collection("reports").doc(reportId).get();
    const data = report.data();
    const visible = report.exists && (profile.role === "admin" || data.createdBy === uid ||
      (data.moderationStatus === "aprobado" &&
        ["pendiente", "en_revision", "en_proceso", "resuelto"].includes(data.status)));
    if (!visible) throw new HttpsError("permission-denied", "No tienes acceso a esta consulta.");

    // Never accept a caller-supplied author UID or return any other profile field.
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

module.exports = {createReportAuthorNameLookup};
