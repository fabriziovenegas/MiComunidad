const test = require("node:test");
const assert = require("node:assert/strict");
const {createContentAuthorNameLookup} = require("../content_author_name");

class HttpsError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
function setup(collection = "projects", role = "vecino") {
  const rows = new Map([
    ["users/viewer", {nombre: "Persona ficticia", role, approvalStatus: "aprobado"}],
    ["users/author", {nombre: "Nombre actual", email: "private@example.com", dni: "00000001", phone: "000000001", address: "Dirección ficticia"}],
    [`${collection}/demo`, {createdBy: "author", isTrashed: false, title: "Contenido ficticio"}],
  ]);
  const reads = [];
  const firestore = {collection: (name) => ({doc: (id) => ({get: async () => {
    const key = `${name}/${id}`;
    reads.push(key);
    return {exists: rows.has(key), data: () => rows.get(key)};
  }})})};
  const lookup = createContentAuthorNameLookup({firestore, HttpsError});
  const request = {auth: {uid: "viewer"}, data: {collection, contentId: "demo"}};
  return {rows, reads, lookup, request};
}
for (const collection of ["projects", "events"]) {
  for (const role of ["vecino", "admin"]) {
    test(`${collection}: ${role} receives only the creator's current name`, async () => {
      const f = setup(collection, role);
      const original = structuredClone(f.rows.get(`${collection}/demo`));
      assert.deepEqual(await f.lookup(f.request), {name: "Nombre actual"});
      f.rows.get("users/author").nombre = "Nombre corregido";
      assert.deepEqual(await f.lookup(f.request), {name: "Nombre corregido"});
      assert.deepEqual(f.rows.get(`${collection}/demo`), original);
      assert.deepEqual(new Set(f.reads), new Set(["users/viewer", `${collection}/demo`, "users/author"]));
    });
  }
  test(`${collection}: caller cannot choose another profile or private fields`, async () => {
    const f = setup(collection);
    assert.deepEqual(await f.lookup({...f.request, data: {...f.request.data,
      authorId: "someone-else", fields: ["email", "dni", "phone"]}}), {name: "Nombre actual"});
    assert.equal(f.reads.includes("users/someone-else"), false);
  });
  test(`${collection}: own content uses the authenticated profile's current name`, async () => {
    const f = setup(collection);
    f.rows.get(`${collection}/demo`).createdBy = "viewer";
    assert.deepEqual(await f.lookup(f.request), {name: "Persona ficticia"});
    assert.deepEqual(f.reads, ["users/viewer", `${collection}/demo`]);
  });
  for (const authorId of [null, "", "../private", "users/author", 123, "x".repeat(129)]) {
    test(`${collection}: malformed historical creator ${JSON.stringify(authorId)} is not a path`, async () => {
      const f = setup(collection); f.rows.get(`${collection}/demo`).createdBy = authorId;
      assert.deepEqual(await f.lookup(f.request), {name: null});
      assert.deepEqual(f.reads, ["users/viewer", `${collection}/demo`]);
    });
  }
  test(`${collection}: missing account/name does not expose other profile fields`, async () => {
    const f = setup(collection);
    for (const name of [null, "", " ", {}, 5, "x".repeat(161)]) {
      f.rows.get("users/author").nombre = name;
      assert.deepEqual(await f.lookup(f.request), {name: null});
    }
    f.rows.delete("users/author");
    assert.deepEqual(await f.lookup(f.request), {name: null});
  });
  test(`${collection}: missing content does not expose its author`, async () => {
    const f = setup(collection); f.rows.delete(`${collection}/demo`);
    await assert.rejects(f.lookup(f.request), {code: "permission-denied"});
    assert.equal(f.reads.includes("users/author"), false);
  });
}
test("archived project is available to an administrator, never a neighbor", async () => {
  const f = setup(); f.rows.get("projects/demo").isTrashed = true;
  await assert.rejects(f.lookup(f.request), {code: "permission-denied"});
  assert.equal(f.reads.includes("users/author"), false);
  f.rows.get("users/viewer").role = "admin";
  assert.deepEqual(await f.lookup(f.request), {name: "Nombre actual"});
});
test("an unspecified project archival flag follows the existing read rule", async () => {
  const f = setup(); delete f.rows.get("projects/demo").isTrashed;
  await assert.rejects(f.lookup(f.request), {code: "permission-denied"});
});
test("authentication is required before any document read", async () => {
  const f = setup();
  await assert.rejects(f.lookup({data: f.request.data}), {code: "unauthenticated"});
  assert.deepEqual(f.reads, []);
});
for (const data of [null, {}, {collection: "users", contentId: "author"}, {collection: "reports", contentId: "demo"},
  ...[null, "", "../private", "a/b", 123, {}, "x".repeat(129)].map((contentId) => ({collection: "projects", contentId}))]) {
  test(`invalid selector ${JSON.stringify(data)} is rejected before reading`, async () => {
    const f = setup();
    await assert.rejects(f.lookup({...f.request, data}), {code: "invalid-argument"});
    assert.deepEqual(f.reads, []);
  });
}
for (const profile of [null, {role: "guest", approvalStatus: "aprobado"}, {role: "admin", approvalStatus: "pendiente"},
  {role: "vecino", approvalStatus: "rechazado"}, {role: "admin", approvalStatus: "aprobado", profileWithdrawalInProgress: true}]) {
  test(`unapproved/withdrawing caller ${JSON.stringify(profile)} cannot look up names`, async () => {
    const f = setup(); if (profile) f.rows.set("users/viewer", profile); else f.rows.delete("users/viewer");
    await assert.rejects(f.lookup(f.request), {code: "permission-denied"});
    assert.deepEqual(f.reads, ["users/viewer"]);
  });
}
