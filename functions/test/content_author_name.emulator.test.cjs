// Loopback emulator only; never uses real community records or credentials.
const {test} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const host = process.env.FIRESTORE_EMULATOR_HOST;
const project = "demo-micomunidad-content-author";
if (host && !/^127\.0\.0\.1:\d+$/.test(host)) throw Error("Only a loopback emulator is allowed.");

test("project/event creator names update while profile privacy stays enforced", {skip: !host}, async (t) => {
  const {initializeApp, deleteApp} = require("firebase-admin/app");
  const {getFirestore} = require("firebase-admin/firestore");
  const {HttpsError} = require("firebase-functions/v2/https");
  const {createContentAuthorNameLookup} = require("../content_author_name");
  const app = initializeApp({projectId: project}, "content-author-local-audit");
  const db = getFirestore(app);
  const lookup = createContentAuthorNameLookup({firestore: db, HttpsError});
  const request = (uid, collection) => ({auth: {uid}, data: {collection, contentId: "demo"}});
  try {
    const rules = await fetch(`http://${host}/emulator/v1/projects/${project}:securityRules`, {
      method: "PUT", headers: {"Content-Type": "application/json"},
      body: JSON.stringify({rules: {files: [{name: "firestore.rules", content: fs.readFileSync(path.join(__dirname, "../../firestore.rules"), "utf8")} ]}}),
    });
    assert.equal(rules.status, 200);
    const reset = await fetch(`http://${host}/emulator/v1/projects/${project}/databases/(default)/documents`, {method: "DELETE"});
    assert.equal(reset.status, 200);
    const batch = db.batch();
    batch.set(db.doc("users/viewer"), {nombre: "Vecino ficticio", role: "vecino", approvalStatus: "aprobado"});
    batch.set(db.doc("users/admin"), {nombre: "Administrador ficticio", role: "admin", approvalStatus: "aprobado"});
    batch.set(db.doc("users/author"), {nombre: "Nombre inicial", email: "private@example.com", dni: "00000001"});
    for (const collection of ["projects", "events"]) {
      batch.set(db.doc(`${collection}/demo`), {createdBy: "author", isTrashed: false, title: "Registro ficticio", description: "No cambia"});
    }
    await batch.commit();
    for (const collection of ["projects", "events"]) {
      await t.test(`${collection}: profile rename changes only the displayed author`, async () => {
        const before = (await db.doc(`${collection}/demo`).get()).data();
        await db.doc("users/author").update({nombre: "Nombre inicial"});
        assert.deepEqual(await lookup(request("viewer", collection)), {name: "Nombre inicial"});
        await db.doc("users/author").update({nombre: "Nombre corregido"});
        assert.deepEqual(await lookup(request("viewer", collection)), {name: "Nombre corregido"});
        assert.deepEqual((await db.doc(`${collection}/demo`).get()).data(), before);
      });
    }
    await t.test("name lookup does not grant direct access to a private profile", async () => {
      const now = Math.floor(Date.now() / 1000);
      const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
      const token = `${encode({alg: "none", typ: "JWT"})}.${encode({iss: `https://securetoken.google.com/${project}`, aud: project, sub: "viewer", user_id: "viewer", iat: now, exp: now + 3600, auth_time: now, firebase: {sign_in_provider: "password"}})}.`;
      const response = await fetch(`http://${host}/v1/projects/${project}/databases/(default)/documents/users/author`, {headers: {Authorization: `Bearer ${token}`}});
      assert.equal(response.status, 403);
    });
    await t.test("archived projects remain restricted to administrators", async () => {
      await db.doc("projects/demo").update({isTrashed: true});
      await assert.rejects(lookup(request("viewer", "projects")), {code: "permission-denied"});
      assert.deepEqual(await lookup(request("admin", "projects")), {name: "Nombre corregido"});
    });
    await t.test("withdrawn callers cannot enumerate creator names", async () => {
      await db.doc("users/viewer").update({profileWithdrawalInProgress: true});
      await assert.rejects(lookup(request("viewer", "events")), {code: "permission-denied"});
    });
  } finally {
    await db.terminate(); await deleteApp(app);
  }
});
