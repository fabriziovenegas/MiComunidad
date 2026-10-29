const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getStorage} = require("firebase-admin/storage");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const nodemailer = require("nodemailer");
const {createProfileIdentity, profileSnapshot} = require("./profile_identity");
const {createAccessRequestSubmission} = require("./access_request_submission");
const {createReportAuthorNameLookup} = require("./report_author_name");
const {createContentAuthorNameLookup} = require("./content_author_name");
const {createContentAttachments} = require("./content_attachments");
const {createEventDeletion} = require("./event_deletion");

initializeApp();

const region = "southamerica-east1";
const communityName = process.env.COMMUNITY_NAME || "MiComunidad";
const communityId = process.env.COMMUNITY_ID || "community";
const profileIdentity = () => createProfileIdentity({
  firestore: getFirestore(), auth: getAuth(), HttpsError, FieldValue,
});

exports.getPublicCommunitySummary = onCall({region}, async () => {
  const firestore = getFirestore();
  const [members, projects] = await Promise.all([
    firestore
        .collection("users")
        .where("approvalStatus", "==", "aprobado")
        .count()
        .get(),
    firestore.collection("projects").count().get(),
  ]);
  return {
    activeMembers: members.data().count,
    projects: projects.data().count,
  };
});

async function requireAdmin(auth) {
  if (!auth || !auth.uid) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  }
  const profile = await getFirestore().collection("users").doc(auth.uid).get();
  const data = profile.data();
  if (!profile.exists || data.role !== "admin" || data.approvalStatus !== "aprobado" || data.profileWithdrawalInProgress === true) {
    throw new HttpsError("permission-denied", "Solo un administrador puede realizar esta acción.");
  }
}

function clean(value) {
  return String(value || "").replace(/[<>&"']/g, "");
}

async function sendEmail({to, subject, html}) {
  const user = process.env.GMAIL_USER;
  const password = process.env.GMAIL_PASSWORD;
  if (!user || !password) {
    console.warn("Correo no enviado: faltan los secretos GMAIL_USER/GMAIL_PASSWORD.");
    return false;
  }
  const transport = nodemailer.createTransport({service: "gmail", auth: {user, pass: password}});
  await transport.sendMail({from: `"${clean(communityName)}" <${user}>`, to, subject, html});
  return true;
}

exports.submitAccessRequest = onCall({region}, (request) => createAccessRequestSubmission({
  identity: profileIdentity(), storage: getStorage, HttpsError,
})(request));

exports.getAccessRequestStatus = onCall({region}, async (request) => {
  const rawDni = request.data?.dni;
  if (typeof rawDni !== "string" || !/^\d{8}$/.test(rawDni.trim())) {
    throw new HttpsError("invalid-argument", "El DNI debe tener 8 dígitos.");
  }
  return profileIdentity().findRequestStatus(rawDni.trim());
});

exports.getReportAuthorName = onCall({region}, (request) => createReportAuthorNameLookup({
  firestore: getFirestore(), HttpsError,
})(request));

exports.getContentAuthorName = onCall({region}, (request) => createContentAuthorNameLookup({
  firestore: getFirestore(), HttpsError,
})(request));

exports.registerContentAttachment = onCall({region}, (request) => createContentAttachments({
  firestore: getFirestore(), storage: getStorage, HttpsError, FieldValue,
}).register(request));

exports.deleteContentAttachment = onCall({region}, (request) => createContentAttachments({
  firestore: getFirestore(), storage: getStorage, HttpsError, FieldValue,
}).remove(request));

exports.deleteCommunityEvent = onCall({region}, (request) => createEventDeletion({
  firestore: getFirestore(), storage: getStorage, HttpsError,
})(request));

// Legacy code-based recovery is unused and deliberately unavailable. The app
// continues using Firebase Authentication's password-reset email flow.
exports.requestPasswordResetCode = onCall({region}, async () => {
  throw new HttpsError("failed-precondition", "Utiliza Recuperar contraseña para solicitar un enlace por correo.");
});

exports.confirmPasswordResetCode = onCall({region}, async () => {
  throw new HttpsError("failed-precondition", "Utiliza el enlace de recuperación enviado por Firebase Authentication.");
});

exports.reviewAccessRequest = onCall({region}, async (request) => {
  await requireAdmin(request.auth);
  if (!request.data || typeof request.data !== "object" || Array.isArray(request.data) ||
      Object.keys(request.data).some((key) => !["requestId", "action", "reason"].includes(key)) ||
      typeof request.data.requestId !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(request.data.requestId) ||
      (request.data.reason != null && (typeof request.data.reason !== "string" || request.data.reason.length > 1000))) {
    throw new HttpsError("invalid-argument", "Solicitud o acción inválida.");
  }
  const requestId = String(request.data?.requestId || "");
  const action = String(request.data?.action || "");
  const reason = clean(request.data?.reason);
  if (!requestId || !["approve", "reject"].includes(action)) {
    throw new HttpsError("invalid-argument", "Solicitud o acción inválida.");
  }
  const reference = getFirestore().collection("accessRequests").doc(requestId);
  const document = await reference.get();
  if (!document.exists) throw new HttpsError("not-found", "La solicitud no existe.");
  const data = document.data();
  const canReview = data.status === "pendiente";
  if (!canReview) {
    throw new HttpsError(
        "failed-precondition",
        "El estado actual de la solicitud no permite esta acción.",
    );
  }

  if (action === "reject") {
    await getFirestore().runTransaction(async (transaction) => {
      const current = await transaction.get(reference);
      if (!current.exists || current.data().status !== "pendiente") {
        throw new HttpsError("failed-precondition", "La solicitud ya fue revisada.");
      }
      transaction.update(reference, {status: "rechazado", rejectionReason: reason || "La solicitud no cumplió los requisitos.", reviewedBy: request.auth.uid, reviewedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
    });
    await sendEmail({to: data.email, subject: "Resultado de tu solicitud", html: `<p>Hola ${clean(data.name)},</p><p>Tu solicitud no fue aprobada.</p><p>Motivo: ${reason || "No especificado"}</p>`});
    return {success: true};
  }

  const existingAccountMessage = "Ya existe una cuenta de Firebase Authentication con este correo. La solicitud requiere revisión y no se ha aprobado.";
  // Only an absent Auth account may be created by this approval. Never attach
  // access to a preexisting account, even if it has no Firestore profile.
  try {
    await getAuth().getUserByEmail(data.email);
    throw new HttpsError("already-exists", existingAccountMessage);
  } catch (error) {
    if (error.code !== "auth/user-not-found") throw error;
  }
  let account;
  try {
    account = await getAuth().createUser({email: data.email, displayName: data.name, emailVerified: false});
  } catch (error) {
    // Also fail closed if another client created the email after the lookup.
    if (error.code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", existingAccountMessage);
    }
    throw error;
  }
  const profile = {
    userId: account.uid,
    nombre: data.name,
    email: data.email,
    phone: data.phone,
    dni: data.dni,
    address: data.address || "",
    timeLivingHere: data.timeLivingHere || "",
    reason: data.reason || "",
    role: "vecino",
    approvalStatus: "aprobado",
    communityId,
    joinDate: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  try {
    await profileIdentity().saveApprovedProfile(reference, account.uid, profile, {
      status: "aprobado", reviewedBy: request.auth.uid,
      reviewedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    const stored = await getFirestore().collection("users").doc(account.uid).get();
    if (!stored.exists) await getAuth().deleteUser(account.uid);
    throw error;
  }
  await getAuth().setCustomUserClaims(account.uid, {
    approved: true,
    role: "vecino",
  });
  const resetLink = await getAuth().generatePasswordResetLink(data.email);
  await sendEmail({to: data.email, subject: `Tu acceso a ${communityName} fue aprobado`, html: `<p>Hola ${clean(data.name)},</p><p>Tu solicitud fue aprobada.</p><p><a href="${resetLink}">Crea tu contraseña para ingresar</a></p>`});
  return {success: true};
});

exports.removeNeighbor = onCall({region}, async (request) => {
  await requireAdmin(request.auth);
  if (!request.data || typeof request.data !== "object" || Array.isArray(request.data) ||
      Object.keys(request.data).some((key) => key !== "userId") ||
      typeof request.data.userId !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(request.data.userId)) {
    throw new HttpsError("invalid-argument", "El usuario no es válido.");
  }
  const userId = String(request.data?.userId || "");
  const profile = await profileIdentity().beginWithdrawal(userId);
  const firestore = getFirestore();
  const requests = firestore.collection("accessRequests");
  const linked = await requests.where("approvedUserId", "==", userId).get();
  const associated = new Map(linked.docs.map((doc) => [doc.id, doc]));
  const dni = String(profile.data().dni || "").trim();
  if (dni) {
    const legacy = await requests.where("dni", "==", dni).get();
    for (const doc of legacy.docs) {
      const original = doc.data();
      const sameEmail = !original.email || !profile.data().email ||
        original.email.toLowerCase() === profile.data().email.toLowerCase();
      if (!original.approvedUserId && original.status === "aprobado" && sameEmail) {
        associated.set(doc.id, doc);
      }
    }
  }
  try {
    await getAuth().deleteUser(userId);
  } catch (error) {
    // Permite reintentar si Authentication se borró en un intento anterior.
    if (error.code !== "auth/user-not-found") throw error;
  }
  const approvedRequests = [...associated.values()]
      .filter((doc) => doc.data().status === "aprobado");
  try {
    for (let offset = 0; offset < approvedRequests.length; offset += 400) {
      const batch = firestore.batch();
      for (const doc of approvedRequests.slice(offset, offset + 400)) {
        batch.update(doc.ref, {
          lookupDni: profile.data().dni || doc.data().lookupDni || doc.data().dni || "",
          currentProfile: profileSnapshot(profile.data(), doc.data()),
          status: "retirado",
          removedUserId: userId,
          removedBy: request.auth.uid,
          removedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  } catch (error) {
    console.error("No se pudo registrar la baja en las solicitudes", error);
    throw new HttpsError(
        "internal",
        "La cuenta fue eliminada, pero quedó pendiente actualizar sus solicitudes. Reintenta retirar al miembro para completar la baja.",
    );
  }
  // Conservamos el perfil hasta registrar las solicitudes, para poder reintentar.
  await profileIdentity().deleteMemberProfile(userId, profile.data());
  return {success: true};
});

exports.setUserRole = onCall({region}, async (request) => {
  await requireAdmin(request.auth);
  if (!request.data || typeof request.data !== "object" || Array.isArray(request.data) ||
      Object.keys(request.data).some((key) => !["userId", "role"].includes(key)) ||
      typeof request.data.userId !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(request.data.userId)) {
    throw new HttpsError("invalid-argument", "Usuario o rol inválido.");
  }
  const userId = String(request.data?.userId || "");
  const role = String(request.data?.role || "");
  if (!userId || !["vecino", "admin"].includes(role)) {
    throw new HttpsError("invalid-argument", "Usuario o rol inválido.");
  }
  if (userId === request.auth.uid) {
    throw new HttpsError(
        "failed-precondition",
        "No puedes cambiar tu propio rol. Otro administrador debe hacerlo.",
    );
  }
  const firestore = getFirestore();
  const users = firestore.collection("users");
  const reference = users.doc(userId);
  await firestore.runTransaction(async (transaction) => {
    // Both profiles must be checked again on every transaction retry. Read in a
    // consistent order when two administrators try to demote each other.
    const profiles = new Map();
    for (const uid of [request.auth.uid, userId].sort()) {
      profiles.set(uid, await transaction.get(users.doc(uid)));
    }
    const actor = profiles.get(request.auth.uid);
    if (!actor.exists || actor.data().role !== "admin" ||
        actor.data().approvalStatus !== "aprobado" || actor.data().profileWithdrawalInProgress === true) {
      throw new HttpsError("permission-denied", "Solo un administrador puede realizar esta acción.");
    }
    const profile = profiles.get(userId);
    if (!profile.exists || profile.data().approvalStatus !== "aprobado") {
      throw new HttpsError("not-found", "El usuario aprobado no existe.");
    }
    if (profile.data().profileWithdrawalInProgress === true) {
      throw new HttpsError("failed-precondition", "La cuenta se está retirando. Actualiza la lista.");
    }
    if (profile.data().role === "admin" && role === "vecino") {
      const admins = await transaction.get(users.where("role", "==", "admin")
          .where("approvalStatus", "==", "aprobado"));
      if (admins.docs.length <= 1) {
        throw new HttpsError("failed-precondition", "Debe quedar al menos un administrador activo.");
      }
    }
    transaction.update(reference, {role, updatedAt: FieldValue.serverTimestamp()});
  });
  // Authentication cannot participate in a Firestore transaction. Synchronize
  // only after commit, using the canonical role if another change superseded it.
  // Never roll a committed role back after a claims error: retrying is safe.
  try {
    for (let attempt = 0; attempt < 3; attempt++) {
      const current = await reference.get();
      if (!current.exists || current.data().approvalStatus !== "aprobado" ||
          !["vecino", "admin"].includes(current.data().role) || current.data().profileWithdrawalInProgress === true) break;
      const account = await getAuth().getUser(userId);
      const currentRole = current.data().role;
      await getAuth().setCustomUserClaims(userId, {...account.customClaims, approved: true, role: currentRole});
      const latest = await reference.get();
      if (latest.exists && latest.data().approvalStatus === "aprobado" &&
          latest.data().role === currentRole && latest.data().profileWithdrawalInProgress !== true) return {success: true};
    }
  } catch (_) {
    // Return an actionable error below without exposing account details.
  }
  throw new HttpsError("internal", "El rol se guardó, pero no se pudo sincronizar el acceso. Actualiza el rol nuevamente para completar el cambio.");
});

exports.updateOwnProfile = onCall({region}, async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  }
  if (!request.data || typeof request.data !== "object" || Array.isArray(request.data) ||
      Object.keys(request.data).some((key) => !["nombre", "dni", "phone", "email", "address", "timeLivingHere", "reason"].includes(key) ||
        typeof request.data[key] !== "string")) {
    throw new HttpsError("invalid-argument", "El perfil contiene campos o tipos no permitidos.");
  }
  return profileIdentity().updateOwnProfile(request.auth.uid, request.data || {});
});
