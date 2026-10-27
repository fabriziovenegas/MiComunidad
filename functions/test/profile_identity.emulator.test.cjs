// Integration checks: official local Firestore/Auth emulators, demo data only.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const host = process.env.FIRESTORE_EMULATOR_HOST;
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const project = 'demo-micomunidad-profile-identity';
if (host && !/^127\.0\.0\.1:\d+$/.test(host)) {
  throw new Error('These tests only accept a loopback Firestore emulator.');
}
if (authHost && !/^127\.0\.0\.1:\d+$/.test(authHost)) {
  throw new Error('These tests only accept a loopback Authentication emulator.');
}

test('profile identity and lookup integration', {skip: !host || !authHost}, async (t) => {
  const {initializeApp, deleteApp} = require('firebase-admin/app');
  const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
  const {getAuth} = require('firebase-admin/auth');
  const {HttpsError} = require('firebase-functions/v2/https');
  const {createProfileIdentity, profileSnapshot} = require('../profile_identity');
  const app = initializeApp({projectId: project}, 'profile-identity-local-test');
  const db = getFirestore(app);
  const auth = getAuth(app);
  const endpoint = `http://${host}/emulator/v1/projects/${project}/databases/(default)/documents`;
  const reset = async () => {
    const response = await fetch(endpoint, {method: 'DELETE'});
    assert.equal(response.status, 200);
    const accounts = await fetch(`http://${authHost}/emulator/v1/projects/${project}/accounts`, {method: 'DELETE'});
    assert.equal(accounts.status, 200);
  };
  t.after(async () => { await reset(); await db.terminate(); await deleteApp(app); });
  await reset();
  const identity = createProfileIdentity({firestore: db, auth, HttpsError, FieldValue});
  const profile = (extra = {}) => ({nombre: 'Demo Resident', dni: '00000001',
    email: 'resident@example.com', phone: '000000001', address: 'Demo address',
    timeLivingHere: '1 a 5 años', reason: 'Original demo reason',
    role: 'vecino', approvalStatus: 'aprobado', ...extra});
  const request = (extra = {}) => ({name: 'Submitted Demo Name', dni: '00000001',
    email: 'submitted@example.com', phone: '000000001', address: 'Submitted demo address',
    timeLivingHere: 'Menos de 1 año', reason: 'Submitted demo reason',
    identityDocumentPath: 'fictional/document', createdAt: Timestamp.fromMillis(1000),
    status: 'aprobado', approvedUserId: 'resident-a', ...extra});
  const changes = (extra = {}) => ({nombre: 'Updated Demo Name', dni: '00000002',
    email: 'updated@example.com', phone: '000000002', address: 'Updated demo address',
    timeLivingHere: '5 a 10 años', reason: 'Updated demo reason', ...extra});
  await db.doc('users/resident-a').set(profile());
  await auth.createUser({uid: 'resident-a', email: 'resident@example.com'});
  const original = request();
  await db.doc('accessRequests/request-a').set(original);
  await db.doc('reports/report-a').set({createdBy: 'resident-a', title: 'Fictional report'});
  await db.doc('reports/report-a/comments/comment-a').set({authorId: 'resident-a', text: 'Fictional comment'});

  await t.test('seven fields, original snapshot, masked response and former DNI', async () => {
    await identity.updateOwnProfile('resident-a', changes());
    const stored = (await db.doc('users/resident-a').get()).data();
    for (const [key, value] of Object.entries(changes())) assert.equal(stored[key], value);
    const application = (await db.doc('accessRequests/request-a').get()).data();
    for (const [key, value] of Object.entries(original)) assert.deepEqual(application[key], value);
    assert.equal((await identity.findRequestStatus('00000001')).request, null);
    const visible = (await identity.findRequestStatus('00000002')).request;
    assert.equal(Object.hasOwn(visible, 'name'), false);
    assert.equal(visible.email, 'up****d@example.com');
    assert.equal(Object.hasOwn(visible, 'phone'), false);
    assert.equal((await db.doc('reports/report-a').get()).data().createdBy, 'resident-a');
    assert.equal((await db.doc('reports/report-a/comments/comment-a').get()).data().authorId, 'resident-a');
    assert.equal((await auth.getUser('resident-a')).email, 'updated@example.com');
  });
  await t.test('a second correction updates the lookup again', async () => {
    await identity.updateOwnProfile('resident-a', changes({dni: '00000003'}));
    assert.equal((await identity.findRequestStatus('00000001')).request, null);
    assert.equal((await identity.findRequestStatus('00000002')).request, null);
    assert.equal((await identity.findRequestStatus('00000003')).request.status, 'aprobado');
  });
  await t.test('a pending request blocks a conflicting correction without partial writes', async () => {
    await db.doc('accessRequests/pending').set(request({dni: '00000004', status: 'pendiente', approvedUserId: null}));
    await assert.rejects(identity.updateOwnProfile('resident-a', changes({dni: '00000004'})), {code: 'already-exists'});
    assert.equal((await db.doc('users/resident-a').get()).data().dni, '00000003');
  });
  await t.test('a real Auth emulator email conflict leaves the stored profile unchanged', async () => {
    await auth.createUser({uid: 'email-conflict', email: 'taken@example.com'});
    await assert.rejects(identity.updateOwnProfile('resident-a', changes({
      dni: '00000003', email: 'taken@example.com',
    })), {code: 'already-exists'});
    assert.equal((await db.doc('users/resident-a').get()).data().email, 'updated@example.com');
    assert.equal((await auth.getUser('resident-a')).email, 'updated@example.com');
  });
  await t.test('the real removal handler retains the corrected DNI after deleting the profile', async () => {
    await db.doc('users/admin-demo').set(profile({role: 'admin', dni: '00000009', email: 'admin@example.com'}));
    const source = fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8');
    const context = {exports: {}, onCall: (_, callback) => callback,
      region: 'local', HttpsError, FieldValue, profileSnapshot,
      getFirestore: () => db, getAuth: () => auth, profileIdentity: () => identity,
      console: {error: () => {}}};
    const guardStart = source.indexOf('async function requireAdmin');
    vm.runInNewContext(source.slice(guardStart, source.indexOf('function clean', guardStart)), context);
    const start = source.indexOf('exports.removeNeighbor =');
    vm.runInNewContext(source.slice(start, source.indexOf('exports.setUserRole =', start)), context);
    await context.exports.removeNeighbor({auth: {uid: 'admin-demo'}, data: {userId: 'resident-a'}});
    assert.equal((await db.doc('users/resident-a').get()).exists, false);
    await assert.rejects(auth.getUser('resident-a'), {code: 'auth/user-not-found'});
    assert.equal((await identity.findRequestStatus('00000001')).request, null);
    const result = (await identity.findRequestStatus('00000003')).request;
    assert.equal(result.status, 'retirado');
    assert.equal(Object.hasOwn(result, 'name'), false);
    assert.equal(result.email, 'up****d@example.com');
    const history = (await db.doc('accessRequests/request-a').get()).data();
    assert.equal(history.dni, '00000001');
    assert.equal(history.reason, 'Submitted demo reason');
  });
  await t.test('re-entry after removal uses a new UID and does not rewrite old requests', async () => {
    const reference = db.doc('accessRequests/re-entry');
    await reference.set(request({dni: '00000003', status: 'pendiente', approvedUserId: null,
      createdAt: Timestamp.fromMillis(2000)}));
    await auth.createUser({uid: 'resident-new', email: 'resident@example.com'});
    await identity.saveApprovedProfile(reference, 'resident-new', profile({dni: '00000003'}), {status: 'aprobado'});
    assert.equal((await identity.findRequestStatus('00000003')).request.status, 'aprobado');
    assert.equal((await db.doc('accessRequests/request-a').get()).data().approvedUserId, 'resident-a');
  });
  await t.test('a claimed DNI cannot be approved for another account', async () => {
    const reference = db.doc('accessRequests/conflicting-approval');
    await reference.set(request({dni: '00000003', status: 'pendiente', approvedUserId: null}));
    await assert.rejects(identity.saveApprovedProfile(reference, 'blocked-user', profile({dni: '00000003'}),
      {status: 'aprobado'}), {code: 'already-exists'});
    assert.equal((await db.doc('users/blocked-user').get()).exists, false);
  });
  await t.test('concurrent updates cannot claim the same DNI in real transactions', async () => {
    await db.doc('users/concurrent-a').set(profile({dni: '00000005', email: 'a@example.com'}));
    await db.doc('users/concurrent-b').set(profile({dni: '00000006', email: 'b@example.com'}));
    const results = await Promise.allSettled([
      identity.updateOwnProfile('concurrent-a', profile({dni: '00000007', email: 'a@example.com'})),
      identity.updateOwnProfile('concurrent-b', profile({dni: '00000007', email: 'b@example.com'})),
    ]);
    assert.equal(results.filter((result) => result.status === 'fulfilled').length, 1);
    assert.equal((await db.collection('users').where('dni', '==', '00000007').get()).size, 1);
  });
  await t.test('Firestore rules keep the server-only DNI index inaccessible to residents', async () => {
    const content = fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8');
    const rules = await fetch(`http://${host}/emulator/v1/projects/${project}:securityRules`, {
      method: 'PUT', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({rules: {files: [{name: 'firestore.rules', content}]}}),
    });
    assert.equal(rules.status, 200);
    const now = Math.floor(Date.now() / 1000);
    const encoded = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
    const token = `${encoded({alg: 'none', typ: 'JWT'})}.${encoded({sub: 'resident-new', user_id: 'resident-new',
      iss: `https://securetoken.google.com/${project}`, aud: project, iat: now, exp: now + 3600,
      auth_time: now, firebase: {sign_in_provider: 'password'}})}.`;
    const key = (await db.collection('memberDniKeys').get()).docs[0].id;
    const url = `http://${host}/v1/projects/${project}/databases/(default)/documents/memberDniKeys/${key}`;
    const denied = await fetch(url, {headers: {Authorization: `Bearer ${token}`}});
    assert.equal(denied.status, 403);
  });
});
