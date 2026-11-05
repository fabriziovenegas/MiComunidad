// Local emulator only: exercise direct client requests, without Flutter.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const host = process.env.FIRESTORE_EMULATOR_HOST;
const project = 'demo-micomunidad-admin-reports';
if (host && !/^127\.0\.0\.1:\d+$/.test(host)) throw Error('Local emulator only');
test('only approved admins can create already approved reports', {skip: !host}, async t => {
  const {initializeApp, deleteApp} = require('firebase-admin/app');
  const {getFirestore} = require('firebase-admin/firestore');
  const app = initializeApp({projectId: project}, 'admin-report-rules');
  const db = getFirestore(app);
  t.after(async () => {
    await fetch(`http://${host}/emulator/v1/projects/${project}/databases/(default)/documents`, {method: 'DELETE'});
    await db.terminate(); await deleteApp(app);
  });
  const response = await fetch(`http://${host}/emulator/v1/projects/${project}:securityRules`, {
    method: 'PUT', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({rules: {files: [{name: 'firestore.rules', content: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8')}]}}),
  });
  assert.equal(response.status, 200, await response.text());
  for (const [uid, role, approvalStatus, extra] of [
    ['admin', 'admin', 'aprobado', {}], ['neighbor', 'vecino', 'aprobado', {}],
    ['pending', 'vecino', 'pendiente', {}], ['unapprovedAdmin', 'admin', 'pendiente', {}],
    ['withdrawn', 'admin', 'aprobado', {profileWithdrawalInProgress: true}],
  ]) await db.doc(`users/${uid}`).set({nombre: 'Fictional', role, approvalStatus, ...extra});
  function token(uid) {
    const e = v => Buffer.from(JSON.stringify(v)).toString('base64url');
    const now = Math.floor(Date.now() / 1000);
    return `${e({alg: 'none', typ: 'JWT'})}.${e({sub: uid, user_id: uid, iss: `https://securetoken.google.com/${project}`, aud: project, iat: now, exp: now + 3600, firebase: {sign_in_provider: 'password'}})}.`;
  }
  let seq = 0;
  async function create(actor, moderationStatus, {owner = actor, status = 'pendiente', extra = {}} = {}) {
    const values = {title: 'Fictional report', description: 'Fictional description', location: '', category: 'obras', priority: 'media', createdBy: owner || 'admin', createdByName: 'Fictional', status, moderationStatus, ...extra};
    const result = await fetch(`http://${host}/v1/projects/${project}/databases/(default)/documents:commit`, {
      method: 'POST', headers: {'Content-Type': 'application/json', ...(actor ? {Authorization: `Bearer ${token(actor)}`} : {})},
      body: JSON.stringify({writes: [{update: {name: `projects/${project}/databases/(default)/documents/reports/test-${++seq}`, fields: Object.fromEntries(Object.entries(values).map(([k, v]) => [k, {stringValue: v}]))}, currentDocument: {exists: false}, updateTransforms: ['createdAt', 'updatedAt'].map(fieldPath => ({fieldPath, setToServerValue: 'REQUEST_TIME'}))}]}),
    });
    return result.status;
  }
  assert.equal(await create('admin', 'aprobado'), 200);
  assert.equal(await create('admin', 'pendiente'), 200); // Older app compatibility.
  assert.equal(await create('neighbor', 'pendiente'), 200);
  assert.equal(await create('neighbor', 'aprobado'), 403);
  for (const actor of [null, 'pending', 'unapprovedAdmin', 'withdrawn']) {
    assert.equal(await create(actor, 'aprobado'), 403);
    assert.equal(await create(actor, 'pendiente'), 403);
  }
  assert.equal(await create('admin', 'aprobado', {owner: 'neighbor'}), 403);
  assert.equal(await create('admin', 'aprobado', {status: 'resuelto'}), 403);
  assert.equal(await create('admin', 'aprobado', {extra: {unexpected: 'field'}}), 403);
});
