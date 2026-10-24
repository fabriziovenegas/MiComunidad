const test = require("node:test");
const assert = require("node:assert/strict");
const {createReportAuthorNameLookup} = require("../report_author_name");

class HttpsError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
function setup({role = "vecino", approved = "aprobado", report = {}, author = {}, missingAuthor = false} = {}) {
  const rows = new Map([
    ["users/viewer", {nombre: "Viewer", role, approvalStatus: approved}],
    ["reports/demo", {createdBy: "author", createdByName: "Old Demo Name", moderationStatus: "aprobado", status: "en_proceso", ...report}],
  ]);
  if (!missingAuthor) rows.set("users/author", {nombre: "Current Demo Name", dni: "00000001", email: "private@example.com", phone: "000000001", address: "Private demo address", role: "admin", ...author});
  const reads = [];
  const firestore = {collection: (collection) => ({doc: (id) => ({get: async () => {
    const key = `${collection}/${id}`;
    reads.push(key);
    return {exists: rows.has(key), data: () => rows.get(key)};
  }})})};
  const lookup = createReportAuthorNameLookup({firestore, HttpsError});
  const request = {auth: {uid: "viewer"}, data: {reportId: "demo"}};
  return {rows, reads, lookup, request};
}

test("returns only the current name, not UID or private profile fields", async () => {
  const f = setup();
  assert.deepEqual(await f.lookup(f.request), {name: "Current Demo Name"});
  assert.deepEqual(f.reads, ["users/viewer", "reports/demo", "users/author"]);
});
test("a corrected profile changes the lookup without changing the original report", async () => {
  const f = setup();
  const before = structuredClone(f.rows.get("reports/demo"));
  assert.deepEqual(await f.lookup(f.request), {name: "Current Demo Name"});
  f.rows.set("users/author", {...f.rows.get("users/author"), nombre: "Corrected Demo Name"});
  assert.deepEqual(await f.lookup(f.request), {name: "Corrected Demo Name"});
  assert.deepEqual(f.rows.get("reports/demo"), before);
});
test("requires authentication before reading documents", async () => {
  const f = setup();
  await assert.rejects(f.lookup({data: {reportId: "demo"}}), {code: "unauthenticated"});
  assert.deepEqual(f.reads, []);
});
for (const reportId of [null, "", "../users/author", "demo/author", {}, 1, "a".repeat(129)]) {
  test(`rejects malformed report ID ${JSON.stringify(reportId)}`, async () => {
    const f = setup();
    await assert.rejects(f.lookup({...f.request, data: {reportId}}), {code: "invalid-argument"});
    assert.deepEqual(f.reads, []);
  });
}
for (const profile of [null, {role: "vecino", approvalStatus: "pendiente"}, {role: "guest", approvalStatus: "aprobado"}, {role: "admin", approvalStatus: "rechazado"}, {role: "vecino", approvalStatus: "aprobado", profileWithdrawalInProgress: true}]) {
  test(`rejects an unavailable or unapproved caller ${JSON.stringify(profile)}`, async () => {
    const f = setup();
    if (profile) f.rows.set("users/viewer", profile); else f.rows.delete("users/viewer");
    await assert.rejects(f.lookup(f.request), {code: "permission-denied"});
    assert.deepEqual(f.reads, ["users/viewer"]);
  });
}
for (const status of ["pendiente", "en_revision", "en_proceso", "resuelto"]) {
  test(`a member can look up the author of an approved ${status} report`, async () => {
    const f = setup({report: {status}});
    assert.deepEqual(await f.lookup(f.request), {name: "Current Demo Name"});
  });
}
for (const report of [{moderationStatus: "pendiente"}, {moderationStatus: "rechazado", status: "rechazado"}, {status: "rechazado"}, {status: "unknown"}]) {
  test(`a member cannot read another author's hidden report ${JSON.stringify(report)}`, async () => {
    const f = setup({report});
    await assert.rejects(f.lookup(f.request), {code: "permission-denied"});
    assert.equal(f.reads.includes("users/author"), false);
  });
  test(`an administrator can read an existing report ${JSON.stringify(report)}`, async () => {
    const f = setup({role: "admin", report});
    assert.deepEqual(await f.lookup(f.request), {name: "Current Demo Name"});
  });
}
for (const status of ["pendiente", "rechazado"]) {
  test(`a member can look up their own ${status} report without a second profile read`, async () => {
    const f = setup({report: {createdBy: "viewer", moderationStatus: status, status}});
    assert.deepEqual(await f.lookup(f.request), {name: "Viewer"});
    assert.deepEqual(f.reads, ["users/viewer", "reports/demo"]);
  });
}
test("missing and inaccessible reports give the same generic error", async () => {
  const f = setup(); f.rows.delete("reports/demo");
  await assert.rejects(f.lookup(f.request), {code: "permission-denied", message: "No tienes acceso a esta consulta."});
  assert.equal(f.reads.includes("users/author"), false);
});
test("caller-supplied author UID and private field selectors are ignored", async () => {
  const f = setup();
  assert.deepEqual(await f.lookup({...f.request, data: {reportId: "demo", authorId: "someone-else", fields: ["dni", "email"]}}), {name: "Current Demo Name"});
  assert.equal(f.reads.includes("users/someone-else"), false);
});
for (const author of [{nombre: ""}, {nombre: "   "}, {nombre: null}, {nombre: {private: "value"}}, {nombre: "x".repeat(161)}]) {
  test(`missing or invalid author name is null, not another profile value ${JSON.stringify(author)}`, async () => {
    const f = setup({author}); assert.deepEqual(await f.lookup(f.request), {name: null});
  });
}
test("an erased account yields null so the app can keep the saved name", async () => {
  const f = setup({missingAuthor: true}); assert.deepEqual(await f.lookup(f.request), {name: null});
});
test("a malformed historical author ID does not become another path", async () => {
  const f = setup({report: {createdBy: "../private"}});
  assert.deepEqual(await f.lookup(f.request), {name: null});
  assert.deepEqual(f.reads, ["users/viewer", "reports/demo"]);
});
test("names are trimmed without returning other fields", async () => {
  const f = setup({author: {nombre: "  Current Demo Name  "}});
  assert.deepEqual(await f.lookup(f.request), {name: "Current Demo Name"});
});
