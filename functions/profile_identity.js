const {createHash} = require("node:crypto");
const {maskPublicEmail} = require("./privacy");

const fields = ["nombre", "dni", "phone", "email", "address", "timeLivingHere", "reason"];
const residenceOptions = ["Menos de 1 año", "1 a 5 años", "5 a 10 años", "Más de 10 años"];

function profileSnapshot(profile, original = {}) {
  return Object.fromEntries(fields.map((key) => {
    const name = key === "nombre" ? "name" : key;
    return [name, profile[key] ?? original[name] ?? ""];
  }));
}

function dateValue(document) {
  const value = document.data().createdAt;
  return value?.toMillis?.() || value?.toDate?.().getTime() || 0;
}

function newest(documents) {
  return [...documents].sort((a, b) => dateValue(b) - dateValue(a) || a.id.localeCompare(b.id));
}

function createProfileIdentity({firestore: db, auth, HttpsError, FieldValue}) {
  const users = db.collection("users");
  const requests = db.collection("accessRequests");
  // Server-only uniqueness records. The existing default-deny rules protect them.
  const keyFor = (dni) => db.collection("memberDniKeys").doc(createHash("sha256").update(dni).digest("hex"));
  const emailValue = (email) => String(email || "").trim().toLowerCase();
  const emailKeyFor = (email) => db.collection("memberEmailKeys").doc(createHash("sha256").update(emailValue(email)).digest("hex"));
  const read = (transaction, reference) => transaction ? transaction.get(reference) : reference.get();

  async function memberFor(data, transaction = null) {
    if (data.approvedUserId) {
      const member = await read(transaction, users.doc(data.approvedUserId));
      return member.exists ? member : null;
    }
    const members = await read(transaction, users.where("dni", "==", data.dni));
    if (members.docs.length !== 1) return null;
    const member = members.docs[0];
    if (data.email && member.data().email &&
        data.email.toLowerCase() !== member.data().email.toLowerCase()) return null;
    return member;
  }

  async function findRequestStatus(dni) {
    const [original, current, members] = await Promise.all([
      requests.where("dni", "==", dni).get(),
      requests.where("lookupDni", "==", dni).get(),
      users.where("dni", "==", dni).get(),
    ]);
    const candidates = new Map([...original.docs, ...current.docs].map((doc) => [doc.id, doc]));
    for (const member of members.docs) {
      const linked = await requests.where("approvedUserId", "==", member.id).get();
      for (const document of linked.docs) {
        if (document.data().status === "aprobado") candidates.set(document.id, document);
      }
    }
    let latest = null;
    for (const document of newest(candidates.values())) {
      const data = document.data();
      let status = data.status;
      let contact = data;
      let lookupDni = data.dni;
      let activeApproval = false;
      if (status === "aprobado" || status === "retirado") {
        const member = status === "aprobado" ? await memberFor(data) : null;
        contact = member ? profileSnapshot(member.data(), data.currentProfile || data) : (data.currentProfile || data);
        lookupDni = member?.data().dni || data.lookupDni || contact.dni || data.dni;
        if (status === "aprobado" && !member) status = "retirado";
        activeApproval = status === "aprobado" && member?.data().approvalStatus === "aprobado" &&
          ["vecino", "admin"].includes(member.data().role);
      }
      // A historical DNI must not keep locating an account after a correction.
      if (lookupDni !== dni) continue;
      const result = {request: {
        status, email: maskPublicEmail(contact.email),
        createdAt: data.createdAt?.toDate?.()?.toISOString?.() || "",
      }};
      // A newer rejected duplicate must not hide the linked approved account.
      if (activeApproval) return result;
      if (!latest) latest = result;
    }
    return latest || {request: null};
  }

  async function assertDniAvailable(transaction, uid, dni, ignoredRequestId = null) {
    const key = await transaction.get(keyFor(dni));
    if (key.exists && key.data().userId !== uid) {
      const owner = await transaction.get(users.doc(key.data().userId));
      if (owner.exists) throw new HttpsError("already-exists", "El DNI ya pertenece a otra cuenta.", {reason: "active-account-conflict"});
    }
    const members = await transaction.get(users.where("dni", "==", dni));
    if (members.docs.some((member) => member.id !== uid)) {
      throw new HttpsError("already-exists", "El DNI ya pertenece a otra cuenta.", {reason: "active-account-conflict"});
    }
    const [original, current] = await Promise.all([
      transaction.get(requests.where("dni", "==", dni)),
      transaction.get(requests.where("lookupDni", "==", dni)),
    ]);
    const candidates = new Map([...original.docs, ...current.docs].map((doc) => [doc.id, doc]));
    for (const document of candidates.values()) {
      const data = document.data();
      if (document.id === ignoredRequestId ||
          (data.status === "aprobado" && data.approvedUserId === uid)) continue;
      if (data.status === "pendiente" && data.dni === dni) {
        throw new HttpsError("already-exists", "Ya existe una solicitud pendiente para ese DNI.");
      }
      if (data.status === "aprobado") {
        const member = await memberFor(data, transaction);
        const effectiveDni = member?.data().dni || data.lookupDni || data.dni;
        if (member && effectiveDni === dni && member.id !== uid) {
          throw new HttpsError("already-exists", "El DNI ya pertenece a otra cuenta.", {reason: "active-account-conflict"});
        }
      }
    }
  }

  async function assertEmailAvailable(transaction, uid, email, ignoredRequestId = null) {
    email = emailValue(email);
    const conflict = (active = false) => new HttpsError("already-exists",
        "Ya existe una solicitud pendiente o una cuenta registrada con este correo. Consulta tu solicitud o recupera tu contraseña si ya tienes una cuenta.",
        active ? {reason: "active-account-conflict"} : undefined);
    // Reading the shared key serializes registrations, approvals and corrections.
    // Check current data rather than letting rejected/withdrawn history reserve it.
    const key = await transaction.get(emailKeyFor(email));
    if (key.exists && key.data().userId !== uid) {
      const owner = await transaction.get(users.doc(key.data().userId));
      if (owner.exists && emailValue(owner.data().email) === email) throw conflict(true);
    }
    const members = await transaction.get(users.where("email", "==", email));
    if (members.docs.some((member) => member.id !== uid)) throw conflict(true);
    // Also cover older pending requests without keys, including mixed-case email.
    const pending = await transaction.get(requests.where("status", "==", "pendiente"));
    if (pending.docs.some((document) => document.id !== ignoredRequestId &&
        emailValue(document.data().email) === email)) throw conflict();
    // Authentication handles case-insensitive existing accounts, even legacy ones
    // without a Firestore profile. No Authentication data is changed here.
    try {
      const account = await auth.getUserByEmail(email);
      if (account.uid !== uid) throw conflict(true);
    } catch (error) {
      if (error.code !== "auth/user-not-found") throw error;
    }
  }

  async function approvedRequest(transaction, uid, previous) {
    const linked = await transaction.get(requests.where("approvedUserId", "==", uid));
    const candidates = linked.docs.filter((document) => document.data().status === "aprobado");
    if (candidates.length) return newest(candidates)[0];
    // Older approvals did not have approvedUserId. Link only an unambiguous match.
    const owners = await transaction.get(users.where("dni", "==", previous.dni || ""));
    if (owners.docs.length !== 1 || owners.docs[0].id !== uid) return null;
    const legacy = await transaction.get(requests.where("dni", "==", previous.dni));
    return newest(legacy.docs.filter((document) => {
      const data = document.data();
      return data.status === "aprobado" && !data.approvedUserId &&
        (!data.email || !previous.email || data.email.toLowerCase() === previous.email.toLowerCase());
    }))[0] || null;
  }

  function normalized(data, previous) {
    if (!data || typeof data !== "object" || Array.isArray(data) ||
        Object.keys(data).some((key) => fields.includes(key) && typeof data[key] !== "string")) {
      throw new HttpsError("invalid-argument", "El perfil contiene campos o tipos no permitidos.");
    }
    const clean = (value) => String(value ?? "").trim();
    const profile = Object.fromEntries(fields.map((key) => [key,
      clean(Object.hasOwn(data, key) ? data[key] : previous[key]),
    ]));
    profile.nombre = profile.nombre.replace(/[<>&"']/g, "");
    profile.email = profile.email.toLowerCase();
    if (Object.hasOwn(data, "timeLivingHere") && profile.timeLivingHere !== previous.timeLivingHere && !residenceOptions.includes(profile.timeLivingHere)) {
      throw new HttpsError("invalid-argument", "Selecciona una opción válida para el tiempo en la comunidad.");
    }
    if (profile.nombre.length < 3 || profile.nombre.length > 160 ||
        !/^\d{8}$/.test(profile.dni) || !/^\d{9}$/.test(profile.phone) ||
        !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(profile.email) || profile.email.length > 320) {
      throw new HttpsError("invalid-argument", "Revisa el nombre, DNI, teléfono y correo del perfil.");
    }
    for (const [key, limit] of [["address", 300], ["timeLivingHere", 100], ["reason", 1000]]) {
      // Older app versions send only four fields; preserve omitted community data.
      if ((Object.hasOwn(data, key) && !profile[key]) || profile[key].length > limit) {
        throw new HttpsError("invalid-argument", "Revisa los datos de la comunidad y su longitud.");
      }
    }
    return profile;
  }

  const fingerprint = (profile) => JSON.stringify([
    ...fields.map((key) => profile[key] || ""), profile.role, profile.approvalStatus,
  ]);
  function requireApproved(document) {
    if (!document.exists || document.data().approvalStatus !== "aprobado" ||
        !["vecino", "admin"].includes(document.data().role) ||
        document.data().profileWithdrawalInProgress === true) {
      throw new HttpsError("permission-denied", "El perfil no está habilitado.");
    }
  }

  async function submitAccessRequest(applicantUid, data) {
    const allowed = ["requestId", "name", "dni", "phone", "email", "address", "timeLivingHere", "reason", "identityDocumentPath", "identityDocumentUrl"];
    if (!data || typeof data !== "object" || Array.isArray(data) ||
        Object.keys(data).some((key) => allowed.includes(key) && typeof data[key] !== "string")) {
      throw new HttpsError("invalid-argument", "La solicitud contiene campos o tipos no permitidos.");
    }
    const requestId = String(data.requestId || "");
    if (!applicantUid || !/^[A-Za-z0-9_-]{1,128}$/.test(requestId)) {
      throw new HttpsError("invalid-argument", "La solicitud no es válida. Inténtalo nuevamente.");
    }
    const profile = Object.fromEntries(fields.map((key) => [key,
      String(data[key === "nombre" ? "name" : key] ?? "").trim(),
    ]));
    profile.email = profile.email.toLowerCase();
    if (!residenceOptions.includes(profile.timeLivingHere)) {
      throw new HttpsError("invalid-argument", "Selecciona una opción válida para el tiempo en la comunidad.");
    }
    if (!profile.nombre || profile.nombre.length > 160 ||
        !/^\d{8}$/.test(profile.dni) || !/^\d{9}$/.test(profile.phone) ||
        !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(profile.email) || profile.email.length > 320) {
      throw new HttpsError("invalid-argument", "Revisa el nombre, DNI, teléfono y correo de la solicitud.");
    }
    for (const [key, limit] of [["address", 300], ["timeLivingHere", 100], ["reason", 1000]]) {
      if (!profile[key] || profile[key].length > limit) {
        throw new HttpsError("invalid-argument", "Revisa los datos de la comunidad y su longitud.");
      }
    }
    const identityDocumentPath = String(data.identityDocumentPath || "");
    const identityDocumentUrl = String(data.identityDocumentUrl || "");
    if (!identityDocumentPath || !identityDocumentUrl || identityDocumentUrl.length > 4096) {
      throw new HttpsError("invalid-argument", "Adjunta tu documento de identidad.");
    }
    const documents = data.identityDocuments;
    if (documents !== undefined && (!Array.isArray(documents) || documents.length < 1 || documents.length > 3 ||
        documents.some((document) => !document || typeof document !== "object" || Array.isArray(document) ||
          Object.keys(document).sort().join(",") !== "contentType,name,size,storagePath,url" ||
          typeof document.storagePath !== "string" || !document.storagePath.startsWith(`access_requests/${applicantUid}/identity/`) ||
          typeof document.url !== "string" || !document.url.startsWith("gs://") || !document.url.endsWith("/" + document.storagePath) ||
          typeof document.name !== "string" || !document.name || document.name.length > 400 ||
          !Number.isInteger(document.size) || document.size < 1 || document.size > 5 * 1024 * 1024 ||
          !["image/jpeg", "image/png", "image/webp", "application/pdf"].includes(document.contentType)) ||
        new Set(documents.map((document) => document.storagePath)).size !== documents.length ||
        documents[0].storagePath !== identityDocumentPath || documents[0].url !== identityDocumentUrl)) {
      throw new HttpsError("invalid-argument", "Los documentos de respaldo no son válidos.");
    }
    const fingerprintParts = [
      applicantUid, ...fields.map((key) => profile[key]), identityDocumentPath,
    ];
    // Preserve the exact historical one-file fingerprint for safe retries.
    if (documents?.length > 1) fingerprintParts.push(documents.slice(1).map((document) => document.storagePath));
    const submissionFingerprint = createHash("sha256").update(JSON.stringify(fingerprintParts)).digest("hex");
    const reference = requests.doc(requestId);
    await db.runTransaction(async (transaction) => {
      const existing = await transaction.get(reference);
      if (existing.exists) {
        if (existing.data().applicantUid === applicantUid &&
            existing.data().submissionFingerprint === submissionFingerprint) return;
        throw new HttpsError("already-exists", "Esta solicitud ya fue registrada.");
      }
      await assertDniAvailable(transaction, applicantUid, profile.dni);
      await assertEmailAvailable(transaction, applicantUid, profile.email);
      transaction.set(reference, {
        applicantUid, ...profileSnapshot(profile), identityDocumentPath, identityDocumentUrl,
        ...(documents ? {identityDocuments: documents} : {}),
        status: "pendiente", submissionFingerprint,
        createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
      });
      // The shared DNI document serializes submissions, approvals and profile
      // corrections. Keeping userId as a UID also supports older backend handlers.
      transaction.set(keyFor(profile.dni), {userId: applicantUid, requestId});
      transaction.set(emailKeyFor(profile.email), {userId: applicantUid, requestId});
    });
    return {requestId};
  }

  async function updateOwnProfile(uid, data) {
    const reference = users.doc(uid);
    const before = await reference.get();
    requireApproved(before);
    const previous = before.data();
    const next = normalized(data, previous);
    // Detect conflicts before touching Authentication, then recheck at commit.
    await db.runTransaction(async (transaction) => {
      const profile = await transaction.get(reference);
      requireApproved(profile);
      if (fingerprint(profile.data()) !== fingerprint(previous)) {
        throw new HttpsError("aborted", "El perfil cambió. Vuelve a cargarlo e inténtalo de nuevo.");
      }
      await assertDniAvailable(transaction, uid, next.dni);
      await assertEmailAvailable(transaction, uid, next.email);
    });
    let authChanged = false;
    try {
      if (next.email !== previous.email || next.nombre !== previous.nombre) {
        await auth.updateUser(uid, {email: next.email, displayName: next.nombre});
        authChanged = true;
      }
      await db.runTransaction(async (transaction) => {
        const profile = await transaction.get(reference);
        requireApproved(profile);
        if (fingerprint(profile.data()) !== fingerprint(previous)) {
          throw new HttpsError("aborted", "El perfil cambió. Vuelve a cargarlo e inténtalo de nuevo.");
        }
        await assertDniAvailable(transaction, uid, next.dni);
        await assertEmailAvailable(transaction, uid, next.email);
        const application = await approvedRequest(transaction, uid, previous);
        const oldKey = previous.dni ? await transaction.get(keyFor(previous.dni)) : null;
        const oldEmailKey = previous.email ? await transaction.get(emailKeyFor(previous.email)) : null;
        // All seven fields and the lookup snapshot commit together in Firestore.
        transaction.update(reference, {...next, updatedAt: FieldValue.serverTimestamp()});
        transaction.set(keyFor(next.dni), {userId: uid});
        transaction.set(emailKeyFor(next.email), {userId: uid});
        if (oldEmailKey?.exists && oldEmailKey.data().userId === uid && emailValue(previous.email) !== next.email) {
          transaction.delete(oldEmailKey.ref);
        }
        if (oldKey?.exists && oldKey.data().userId === uid && previous.dni !== next.dni) {
          transaction.delete(oldKey.ref);
        }
        if (application) {
          transaction.update(application.ref, {
            approvedUserId: uid, lookupDni: next.dni, currentProfile: profileSnapshot(next),
            profileUpdatedAt: FieldValue.serverTimestamp(),
          });
        }
      });
    } catch (error) {
      if (authChanged) {
        // Auth and Firestore cannot share a transaction. Restore the canonical
        // profile if its Firestore commit failed; never log personal values.
        try {
          const canonical = await reference.get();
          if (canonical.exists) {
            await auth.updateUser(uid, {email: canonical.data().email, displayName: canonical.data().nombre});
          }
        } catch (_) {
          throw new HttpsError("internal", "No se completó la actualización. Reintenta guardar el perfil para sincronizar la cuenta.");
        }
      }
      if (error.code === "auth/email-already-exists") {
        throw new HttpsError("already-exists", "El correo ya está registrado.");
      }
      if (error.code === "auth/invalid-email") {
        throw new HttpsError("invalid-argument", "El correo no es válido.");
      }
      throw error;
    }
    return {success: true};
  }

  async function saveApprovedProfile(reference, uid, profile, review) {
    await db.runTransaction(async (transaction) => {
      const application = await transaction.get(reference);
      const member = await transaction.get(users.doc(uid));
      if (!application.exists || application.data().status !== "pendiente") {
        throw new HttpsError("failed-precondition", "La solicitud ya fue revisada.");
      }
      if (member.exists) throw new HttpsError("already-exists", "La cuenta ya tiene un perfil.");
      await assertDniAvailable(transaction, uid, profile.dni, reference.id);
      await assertEmailAvailable(transaction, uid, profile.email, reference.id);
      transaction.set(users.doc(uid), profile);
      transaction.set(keyFor(profile.dni), {userId: uid});
      transaction.set(emailKeyFor(profile.email), {userId: uid});
      transaction.update(reference, {...review, approvedUserId: uid, lookupDni: profile.dni,
        currentProfile: profileSnapshot(profile)});
    });
  }

  async function deleteMemberProfile(uid, profile) {
    await db.runTransaction(async (transaction) => {
      const key = profile.dni ? await transaction.get(keyFor(profile.dni)) : null;
      const emailKey = profile.email ? await transaction.get(emailKeyFor(profile.email)) : null;
      transaction.delete(users.doc(uid));
      if (key?.exists && key.data().userId === uid) transaction.delete(key.ref);
      if (emailKey?.exists && emailKey.data().userId === uid) transaction.delete(emailKey.ref);
    });
  }

  async function beginWithdrawal(uid) {
    return db.runTransaction(async (transaction) => {
      const profile = await transaction.get(users.doc(uid));
      if (!profile.exists || profile.data().role !== "vecino") {
        throw new HttpsError("failed-precondition", "Solo se puede retirar a un vecino.");
      }
      // Freeze new profile corrections before capturing data for withdrawal.
      // Keep the profile for an administrator's retry if a later step fails.
      transaction.update(profile.ref, {profileWithdrawalInProgress: true});
      return profile;
    });
  }

  return {findRequestStatus, submitAccessRequest, updateOwnProfile, saveApprovedProfile, deleteMemberProfile, beginWithdrawal};
}

module.exports = {createProfileIdentity, profileSnapshot};
