const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {createHash, randomInt} = require("crypto");
const nodemailer = require("nodemailer");
const {maskPublicEmail} = require("./privacy");

initializeApp();

const emailSecrets = ["GMAIL_USER", "GMAIL_PASSWORD"];
const region = "southamerica-east1";
const communityName = process.env.COMMUNITY_NAME || "MiComunidad";
const communityId = process.env.COMMUNITY_ID || "community";

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
  if (!profile.exists || data.role !== "admin" || data.approvalStatus !== "aprobado") {
    throw new HttpsError("permission-denied", "Solo un administrador puede realizar esta acción.");
  }
}

function clean(value) {
  return String(value || "").replace(/[<>&"']/g, "");
}

function hash(value) {
  return createHash("sha256").update(value).digest("hex");
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

exports.getAccessRequestStatus = onCall({region}, async (request) => {
  const dni = String(request.data?.dni || "").trim();
  if (!/^\d{8}$/.test(dni)) {
    throw new HttpsError("invalid-argument", "El DNI debe tener 8 dígitos.");
  }
  const result = await getFirestore().collection("accessRequests").where("dni", "==", dni).orderBy("createdAt", "desc").limit(1).get();
  if (result.empty) return {request: null};
  const data = result.docs[0].data();
  let status = data.status;
  // Las bajas anteriores pueden conservar solicitudes aprobadas sin perfil.
  // Esta consulta solo interpreta el estado; no migra documentos históricos.
  if (status === "aprobado") {
    const member = data.approvedUserId ?
      await getFirestore().collection("users").doc(data.approvedUserId).get() :
      await getFirestore().collection("users").where("dni", "==", dni).limit(1).get();
    if (data.approvedUserId ? !member.exists : member.empty) status = "retirado";
  }
  return {request: {name: data.name, email: maskPublicEmail(data.email), status, rejectionReason: data.rejectionReason || null, createdAt: data.createdAt?.toDate().toISOString() || ""}};
});

exports.requestPasswordResetCode = onCall(
    {region, secrets: emailSecrets},
    async (request) => {
      const email = String(request.data?.email || "").trim().toLowerCase();
      if (!/^\S+@\S+\.\S+$/.test(email)) {
        throw new HttpsError("invalid-argument", "Ingresa un correo válido.");
      }

      let account;
      try {
        account = await getAuth().getUserByEmail(email);
      } catch (error) {
        if (error.code === "auth/user-not-found") {
          return {success: true};
        }
        throw error;
      }

      const profile = await getFirestore().collection("users").doc(account.uid).get();
      if (!profile.exists || profile.data().approvalStatus !== "aprobado") {
        return {success: true};
      }

      const code = String(randomInt(100000, 1000000));
      const reference = getFirestore().collection("passwordResetCodes").doc(hash(email));
      await reference.set({
        userId: account.uid,
        email,
        codeHash: hash(`${email}:${code}`),
        attemptsRemaining: 3,
        expiresAt: Timestamp.fromMillis(Date.now() + 10 * 60 * 1000),
        createdAt: FieldValue.serverTimestamp(),
      });
      const sent = await sendEmail({
        to: email,
        subject: "Código para recuperar tu contraseña",
        html: `<p>Tu código de recuperación es <strong>${code}</strong>.</p><p>Caduca en 10 minutos y permite hasta 3 intentos.</p>`,
      });
      if (!sent) {
        await reference.delete();
        throw new HttpsError(
            "failed-precondition",
            "El servicio de correo todavía no está configurado.",
        );
      }
      return {success: true};
    },
);

exports.confirmPasswordResetCode = onCall({region}, async (request) => {
  const email = String(request.data?.email || "").trim().toLowerCase();
  const code = String(request.data?.code || "").trim();
  const newPassword = String(request.data?.newPassword || "");
  if (!/^\S+@\S+\.\S+$/.test(email) || !/^\d{6}$/.test(code)) {
    throw new HttpsError("invalid-argument", "Correo o código inválido.");
  }
  if (newPassword.length < 8) {
    throw new HttpsError(
        "invalid-argument",
        "La contraseña debe tener al menos 8 caracteres.",
    );
  }

  const reference = getFirestore().collection("passwordResetCodes").doc(hash(email));
  const verification = await getFirestore().runTransaction(async (transaction) => {
    const document = await transaction.get(reference);
    if (!document.exists) {
      return {error: "not-found", message: "Solicita un código nuevo."};
    }
    const data = document.data();
    if (data.expiresAt.toMillis() < Date.now()) {
      transaction.delete(reference);
      return {error: "deadline-exceeded", message: "El código venció. Solicita otro."};
    }
    if (data.attemptsRemaining <= 0) {
      transaction.delete(reference);
      return {error: "resource-exhausted", message: "Se agotaron los intentos."};
    }
    if (data.codeHash !== hash(`${email}:${code}`)) {
      const remaining = data.attemptsRemaining - 1;
      transaction.update(reference, {attemptsRemaining: remaining});
      return {
        error: "permission-denied",
        message: remaining > 0 ? `Código incorrecto. Quedan ${remaining} intentos.` : "Se agotaron los intentos.",
      };
    }
    transaction.delete(reference);
    return {userId: data.userId};
  });
  if (verification.error) {
    throw new HttpsError(verification.error, verification.message);
  }
  await getAuth().updateUser(verification.userId, {password: newPassword});
  return {success: true};
});

exports.reviewAccessRequest = onCall({region}, async (request) => {
  await requireAdmin(request.auth);
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
  const canReview = action === "approve" ?
    ["pendiente", "rechazado"].includes(data.status) :
    data.status === "pendiente";
  if (!canReview) {
    throw new HttpsError(
        "failed-precondition",
        "El estado actual de la solicitud no permite esta acción.",
    );
  }

  if (action === "reject") {
    await reference.update({status: "rechazado", rejectionReason: reason || "La solicitud no cumplió los requisitos.", reviewedBy: request.auth.uid, reviewedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
    await sendEmail({to: data.email, subject: "Resultado de tu solicitud", html: `<p>Hola ${clean(data.name)},</p><p>Tu solicitud no fue aprobada.</p><p>Motivo: ${reason || "No especificado"}</p>`});
    return {success: true};
  }

  let account;
  let createdAccount = false;
  try {
    account = await getAuth().getUserByEmail(data.email);
    const existingProfile = await getFirestore().collection("users").doc(account.uid).get();
    if (existingProfile.exists) {
      throw new HttpsError(
          "already-exists",
          "El correo ya pertenece a una cuenta registrada.",
      );
    }
  } catch (error) {
    if (error.code !== "auth/user-not-found") throw error;
    account = await getAuth().createUser({email: data.email, displayName: data.name, emailVerified: false});
    createdAccount = true;
  }
  const repeatedDni = await getFirestore()
      .collection("users")
      .where("dni", "==", data.dni)
      .limit(1)
      .get();
  if (!repeatedDni.empty) {
    if (createdAccount) {
      await getAuth().deleteUser(account.uid);
    }
    throw new HttpsError(
        "already-exists",
        "El DNI ya pertenece a un vecino registrado.",
    );
  }
  await getFirestore().collection("users").doc(account.uid).set({
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
  }, {merge: true});
  await getAuth().setCustomUserClaims(account.uid, {
    approved: true,
    role: "vecino",
  });
  await reference.update({status: "aprobado", approvedUserId: account.uid, reviewedBy: request.auth.uid, reviewedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
  const resetLink = await getAuth().generatePasswordResetLink(data.email);
  await sendEmail({to: data.email, subject: `Tu acceso a ${communityName} fue aprobado`, html: `<p>Hola ${clean(data.name)},</p><p>Tu solicitud fue aprobada.</p><p><a href="${resetLink}">Crea tu contraseña para ingresar</a></p>`});
  return {success: true};
});

exports.removeNeighbor = onCall({region}, async (request) => {
  await requireAdmin(request.auth);
  const userId = String(request.data?.userId || "");
  const profile = await getFirestore().collection("users").doc(userId).get();
  if (!profile.exists || profile.data().role !== "vecino") {
    throw new HttpsError("failed-precondition", "Solo se puede retirar a un vecino.");
  }
  const firestore = getFirestore();
  const requests = firestore.collection("accessRequests");
  const linked = await requests.where("approvedUserId", "==", userId).get();
  const associated = new Map(linked.docs.map((doc) => [doc.id, doc]));
  const dni = String(profile.data().dni || "").trim();
  if (dni) {
    const legacy = await requests.where("dni", "==", dni).get();
    for (const doc of legacy.docs) {
      if (!doc.data().approvedUserId && doc.data().status === "aprobado") {
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
  await profile.ref.delete();
  return {success: true};
});

exports.setUserRole = onCall({region}, async (request) => {
  await requireAdmin(request.auth);
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
  const reference = getFirestore().collection("users").doc(userId);
  const profile = await reference.get();
  if (!profile.exists || profile.data().approvalStatus !== "aprobado") {
    throw new HttpsError("not-found", "El usuario aprobado no existe.");
  }
  if (profile.data().role === "admin" && role === "vecino") {
    const admins = await getFirestore()
        .collection("users")
        .where("role", "==", "admin")
        .where("approvalStatus", "==", "aprobado")
        .get();
    if (admins.size <= 1) {
      throw new HttpsError(
          "failed-precondition",
          "Debe quedar al menos un administrador activo.",
      );
    }
  }
  await reference.update({role, updatedAt: FieldValue.serverTimestamp()});
  await getAuth().setCustomUserClaims(userId, {approved: true, role});
  return {success: true};
});

exports.updateOwnProfile = onCall({region}, async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  }
  const nombre = clean(request.data?.nombre).trim();
  const dni = String(request.data?.dni || "").trim();
  const phone = String(request.data?.phone || "").trim();
  const email = String(request.data?.email || "").trim().toLowerCase();
  if (nombre.length < 3 || !/^\d{8}$/.test(dni) ||
      !/^\d{9}$/.test(phone) || !/^\S+@\S+\.\S+$/.test(email)) {
    throw new HttpsError("invalid-argument", "Revisa los datos del perfil.");
  }
  const reference = getFirestore().collection("users").doc(request.auth.uid);
  const profile = await reference.get();
  if (!profile.exists || profile.data().approvalStatus !== "aprobado") {
    throw new HttpsError("permission-denied", "El perfil no está habilitado.");
  }
  const repeatedDni = await getFirestore()
      .collection("users").where("dni", "==", dni).get();
  if (repeatedDni.docs.some((document) => document.id !== request.auth.uid)) {
    throw new HttpsError("already-exists", "El DNI ya está registrado.");
  }
  try {
    await getAuth().updateUser(request.auth.uid, {email, displayName: nombre});
  } catch (error) {
    if (error.code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", "El correo ya está registrado.");
    }
    throw error;
  }
  await reference.update({
    nombre,
    dni,
    phone,
    email,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return {success: true};
});
