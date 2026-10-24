// Official loopback emulator only. No production project or credentials.
const {test} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const host = process.env.FIRESTORE_EMULATOR_HOST;
const project = "demo-micomunidad-report-author";
if (host && !/^127\.0\.0\.1:\d+$/.test(host)) throw Error("Only a loopback emulator is allowed.");

test("report name lookup and unchanged profile privacy in the Firestore emulator", {skip: !host}, async (t) => {
  const {initializeApp, deleteApp} = require("firebase-admin/app");
  const {getFirestore} = require("firebase-admin/firestore");
  const {HttpsError} = require("firebase-functions/v2/https");
  const {createReportAuthorNameLookup} = require("../report_author_name");
  const app = initializeApp({projectId: project}, "report-author-name-local-test");
  const db = getFirestore(app);
  const lookup = createReportAuthorNameLookup({firestore: db, HttpsError});
  const base = `http://${host}/v1/projects/${project}/databases/(default)/documents`;
  const request = (uid, reportId) => ({auth: {uid}, data: {reportId}});
  try {
    const ruleResponse = await fetch(`http://${host}/emulator/v1/projects/${project}:securityRules`, {
      method: "PUT", headers: {"Content-Type": "application/json"},
      body: JSON.stringify({rules: {files: [{name: "firestore.rules", content: fs.readFileSync(path.join(__dirname, "../../firestore.rules"), "utf8")} ]}}),
    });
    assert.equal(ruleResponse.status, 200);
    const reset = await fetch(`http://${host}/emulator/v1/projects/${project}/databases/(default)/documents`, {method: "DELETE"});
    assert.equal(reset.status, 200);
    const batch = db.batch();
    for (const [uid, role, approvalStatus] of [["viewer", "vecino", "aprobado"], ["admin", "admin", "aprobado"], ["pending", "vecino", "pendiente"]]) {
      batch.set(db.doc(`users/${uid}`), {nombre: "Fictional Viewer", role, approvalStatus});
    }
    batch.set(db.doc("users/author"), {nombre: "Current Fictional Author", dni: "00000001", phone: "000000001", email: "private@example.com", address: "Fictional private address", role: "vecino", approvalStatus: "aprobado"});
    batch.set(db.doc("reports/visible"), {createdBy: "author", createdByName: "Original Fictional Author", status: "resuelto", moderationStatus: "aprobado"});
    batch.set(db.doc("reports/hidden"), {createdBy: "author", createdByName: "Original Fictional Author", status: "pendiente", moderationStatus: "pendiente"});
    batch.set(db.doc("reports/own-hidden"), {createdBy: "viewer", createdByName: "Original Viewer", status: "rechazado", moderationStatus: "rechazado"});
    await batch.commit();

    await t.test("an approved resident receives exactly one name field", async () => {
      assert.deepEqual(await lookup(request("viewer", "visible")), {name: "Current Fictional Author"});
    });
    await t.test("a profile correction changes the response without rewriting the report", async () => {
      const before = (await db.doc("reports/visible").get()).data();
      await db.doc("users/author").update({nombre: "Corrected Fictional Author"});
      assert.deepEqual(await lookup(request("viewer", "visible")), {name: "Corrected Fictional Author"});
      assert.deepEqual((await db.doc("reports/visible").get()).data(), before);
    });
    await t.test("hidden foreign, missing and unapproved lookups are denied", async () => {
      for (const [uid, id] of [["viewer", "hidden"], ["viewer", "absent"], ["pending", "visible"]]) {
        await assert.rejects(lookup(request(uid, id)), {code: "permission-denied"});
      }
      await assert.rejects(lookup({data: {reportId: "visible"}}), {code: "unauthenticated"});
    });
    await t.test("own rejected reports and administrator moderation lookups remain available", async () => {
      assert.deepEqual(await lookup(request("viewer", "own-hidden")), {name: "Fictional Viewer"});
      assert.deepEqual(await lookup(request("admin", "hidden")), {name: "Corrected Fictional Author"});
    });
    await t.test("the same resident still cannot directly read the author's private profile", async () => {
      const now = Math.floor(Date.now() / 1000);
      const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
      const jwt = `${encode({alg: "none", typ: "JWT"})}.${encode({iss: `https://securetoken.google.com/${project}`, aud: project, sub: "viewer", user_id: "viewer", iat: now, exp: now + 3600, auth_time: now, firebase: {sign_in_provider: "password"}})}.`;
      const response = await fetch(`${base}/users/author`, {headers: {Authorization: `Bearer ${jwt}`}});
      assert.equal(response.status, 403);
    });
    await t.test("a removed account returns null and leaves original records intact", async () => {
      await db.doc("users/author").delete();
      assert.deepEqual(await lookup(request("viewer", "visible")), {name: null});
      assert.equal((await db.doc("reports/visible").get()).data().createdByName, "Original Fictional Author");
    });
  } finally {
    await db.terminate(); await deleteApp(app);
  }
});
