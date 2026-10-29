// Fictional data and the loopback Firestore emulator only. No production access.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const host = process.env.FIRESTORE_EMULATOR_HOST;
const project = 'demo-micomunidad-rejected-history';
if (host && !/^127\.0\.0\.1:\d+$/.test(host)) throw Error('Loopback emulator required');

test('rejected requests remain private history and cannot be deleted through client APIs', {skip: !host}, async t => {
  const {initializeApp, deleteApp} = require('firebase-admin/app');
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const {createProfileIdentity} = require('../profile_identity');
  const app = initializeApp({projectId: project}, 'rejected-history-local');
  const db = getFirestore(app);
  const base = `http://${host}/v1/projects/${project}/databases/(default)/documents`;
  const reset = async () => {
    const r = await fetch(`http://${host}/emulator/v1/projects/${project}/databases/(default)/documents`, {method: 'DELETE'});
    assert.equal(r.status, 200); await r.text();
  };
  t.after(async () => {await reset(); await db.terminate(); await deleteApp(app);});
  await reset();
  const rules = await fetch(`http://${host}/emulator/v1/projects/${project}:securityRules`, {
    method: 'PUT', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({rules: {files: [{name: 'firestore.rules',
      content: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8')}]}}),
  });
  assert.equal(rules.status, 200, await rules.text());
  function token(uid) {
    const now = Math.floor(Date.now() / 1000);
    const encode = v => Buffer.from(JSON.stringify(v)).toString('base64url');
    return `${encode({alg: 'none', typ: 'JWT'})}.${encode({sub: uid, user_id: uid,
      iss: `https://securetoken.google.com/${project}`, aud: project, iat: now,
      exp: now + 3600, auth_time: now, firebase: {sign_in_provider: 'password'}})}.`;
  }
  async function request(document, actor, method = 'GET', fields) {
    const r = await fetch(`${base}/${document}`, {method,
      headers: {'Content-Type': 'application/json', ...(actor ? {Authorization: `Bearer ${token(actor)}`} : {})},
      ...(fields ? {body: JSON.stringify({fields})} : {}),
    });
    const body = await r.json(); return {status: r.status, body};
  }
  for (const [uid, role, approvalStatus] of [
    ['admin', 'admin', 'aprobado'], ['neighbor', 'vecino', 'aprobado'],
    ['pending', 'vecino', 'pendiente'], ['former', 'vecino', 'retirado'],
  ]) await db.doc(`users/${uid}`).set({nombre: 'Fictional person', role, approvalStatus});
  const original = {dni: '00000001', email: 'fictional@example.com', status: 'rechazado',
    rejectionReason: 'Fictional internal reason', createdAt: Timestamp.fromMillis(2000)};
  await db.doc('accessRequests/rejected').set(original);
  await db.doc('accessRequests/previous-withdrawal').set({dni: '00000001', email: original.email,
    status: 'retirado', removedUserId: 'previous-fictional-user', createdAt: Timestamp.fromMillis(1000)});
  const identity = createProfileIdentity({firestore: db});

  await t.test('even an approved administrator cannot delete a rejected request', async () => {
    for (const actor of ['admin', 'neighbor', 'pending', 'former', null]) {
      const result = await request('accessRequests/rejected', actor, 'DELETE');
      assert.equal(result.status, 403, JSON.stringify(result.body));
      assert.deepEqual((await db.doc('accessRequests/rejected').get()).data(), original);
    }
  });
  await t.test('administrator can still read the internal reason; others cannot', async () => {
    const admin = await request('accessRequests/rejected', 'admin');
    assert.equal(admin.status, 200);
    assert.equal(admin.body.fields.rejectionReason.stringValue, original.rejectionReason);
    for (const actor of ['neighbor', 'pending', 'former', null]) {
      assert.equal((await request('accessRequests/rejected', actor)).status, 403);
    }
  });
  await t.test('changing or replacing its status cannot bypass retention', async () => {
    const result = await request('accessRequests/rejected', 'admin', 'PATCH', {status: {stringValue: 'pendiente'}});
    assert.equal(result.status, 403, JSON.stringify(result.body));
    assert.deepEqual((await db.doc('accessRequests/rejected').get()).data(), original);
  });
  await t.test('public lookup keeps the latest rejection without exposing its reason', async () => {
    const visible = (await identity.findRequestStatus('00000001')).request;
    assert.equal(visible.status, 'rechazado');
    assert.deepEqual(Object.keys(visible).sort(), ['createdAt', 'email', 'status']);
    assert.notEqual(visible.email, original.email);
    assert.equal(visible.createdAt, original.createdAt.toDate().toISOString());
    assert.equal((await db.doc('accessRequests/previous-withdrawal').get()).data().status, 'retirado');
  });
  await t.test('a genuine previous withdrawal still appears as withdrawn', async () => {
    await db.doc('accessRequests/other-withdrawal').set({dni: '00000002', email: original.email,
      status: 'retirado', createdAt: Timestamp.fromMillis(1000)});
    assert.equal((await identity.findRequestStatus('00000002')).request.status, 'retirado');
  });
  await t.test('the existing deletion permissions for other request states are unchanged', async () => {
    for (const status of ['pendiente', 'aprobado', 'retirado', null]) {
      const ref = db.doc(`accessRequests/other-${status || 'legacy'}`);
      await ref.set(status ? {status} : {name: 'Fictional legacy record'});
      assert.equal((await request(ref.path, 'neighbor', 'DELETE')).status, 403);
      const result = await request(ref.path, 'admin', 'DELETE');
      assert.equal(result.status, 200, JSON.stringify(result.body));
      assert.equal((await ref.get()).exists, false);
    }
  });
  await t.test('unrelated administrative comment deletion still works', async () => {
    await db.doc('events/fictional').set({title: 'Fictional meeting'});
    const ref = db.doc('events/fictional/comments/fictional');
    await ref.set({text: 'Fictional comment', authorId: 'neighbor'});
    assert.equal((await request(ref.path, 'admin', 'DELETE')).status, 200);
  });
});
