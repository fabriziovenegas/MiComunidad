const {storedObjectPath} = require("./content_attachments");

// Definitive deletion only. Does not participate in editing or archiving.
function createEventDeletion({firestore: db, storage, HttpsError}) {
  async function requireAdmin(uid, transaction) {
    const ref = db.collection("users").doc(uid);
    const snapshot = transaction ? await transaction.get(ref) : await ref.get();
    const profile = snapshot.data();
    if (!snapshot.exists || profile.role !== "admin" || profile.approvalStatus !== "aprobado" ||
        profile.profileWithdrawalInProgress === true) {
      throw new HttpsError("permission-denied", "Solo un administrador puede eliminar actividades.");
    }
  }

  return async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
    const data = request.data;
    if (!data || typeof data !== "object" || Array.isArray(data) ||
        Object.keys(data).length !== 1 || typeof data.eventId !== "string" ||
        !/^[A-Za-z0-9_-]{1,128}$/.test(data.eventId)) {
      throw new HttpsError("invalid-argument", "La actividad no es válida.");
    }
    await requireAdmin(uid);
    const reference = db.collection("events").doc(data.eventId);
    const bucket = storage().bucket();
    const prefix = `events/${data.eventId}/`;
    const belongs = (path) => typeof path === "string" && path.startsWith(prefix) && path.length > prefix.length;

    // Validate every stored reference before changing anything. A poisoned
    // attachment must never redirect an administrative deletion elsewhere.
    const collections = await reference.listCollections();
    for (const collection of collections) {
      let query = collection.orderBy("__name__").limit(400);
      while (true) {
        const page = await query.get();
        for (const document of page.docs) {
          const saved = document.data();
          for (const field of ["storagePath", "url"]) {
            if (saved[field] == null) continue;
            const path = storedObjectPath({[field]: saved[field]}, bucket.name);
            if (!belongs(path)) {
              throw new HttpsError("failed-precondition",
                  "Un adjunto no pertenece a esta actividad. No se eliminó la actividad.");
            }
          }
          if (saved.storagePath && saved.url &&
              storedObjectPath({url: saved.url}, bucket.name) !== saved.storagePath) {
            throw new HttpsError("failed-precondition",
                "Las referencias de un adjunto requieren revisión. No se eliminó la actividad.");
          }
        }
        if (page.docs.length < 400) break;
        query = collection.orderBy("__name__").startAfter(page.docs.at(-1)).limit(400);
      }
    }

    // Existing rules already require the event to exist for new contributions.
    // Removing the parent first closes those paths, without changing permissions.
    // A retry also cleans an already-removed parent after a partial failure.
    await db.runTransaction(async (transaction) => {
      await requireAdmin(uid, transaction);
      const current = await transaction.get(reference);
      if (current.exists) transaction.delete(reference);
    });
    try {
      let next;
      do {
        const [files, following] = await bucket.getFiles({prefix, autoPaginate: false, maxResults: 200,
          ...(next ? {pageToken: next} : {})});
        if (files.some((file) => !belongs(file.name))) throw Error("Unexpected object outside activity");
        for (let offset = 0; offset < files.length; offset += 8) {
          const results = await Promise.allSettled(files.slice(offset, offset + 8).map(async (file) => {
            try {
              const metadata = file.metadata?.generation ? file.metadata : (await file.getMetadata())[0];
              await bucket.file(file.name, {generation: metadata.generation}).delete();
            } catch (error) {
              if (error.code !== 404) throw error;
            }
          }));
          const failed = results.find((result) => result.status === "rejected");
          if (failed) throw failed.reason;
        }
        next = following?.pageToken;
      } while (next);
      await requireAdmin(uid);
      // This includes photos, minutes, comments and any nested attachment records.
      for (const collection of await reference.listCollections()) {
        await db.recursiveDelete(collection);
      }
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("unavailable",
          "No se pudo completar la eliminación de la actividad. Reintenta para terminar de eliminar sus archivos.",
          {reason: "event-deletion-incomplete"});
    }
    return {success: true};
  };
}

module.exports = {createEventDeletion};
