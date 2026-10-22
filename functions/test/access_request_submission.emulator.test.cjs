// Official loopback Firestore/Auth emulators only; Storage metadata is simulated.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const host = process.env.FIRESTORE_EMULATOR_HOST;
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const project = 'demo-micomunidad-access-requests';
for (const value of [host, authHost]) {
  if (value && !/^127\.0\.0\.1:\d+$/.test(value)) throw Error('Loopback emulators required.');
}

test('atomic access requests and current-DNI lookup', {skip: !host || !authHost}, async (t) => {
  const {initializeApp, deleteApp} = require('firebase-admin/app');
  const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
  const {getAuth} = require('firebase-admin/auth');
  const {HttpsError} = require('firebase-functions/v2/https');
  const {createProfileIdentity, profileSnapshot} = require('../profile_identity');
  const {createAccessRequestSubmission} = require('../access_request_submission');
  const app = initializeApp({projectId: project}, 'access-request-local-test');
  const db = getFirestore(app);
  const auth = getAuth(app);
  const base = `http://${host}/v1/projects/${project}/databases/(default)/documents`;
  const reset = async () => {
    for (const url of [`http://${host}/emulator/v1/projects/${project}/databases/(default)/documents`,
      `http://${authHost}/emulator/v1/projects/${project}/accounts`]) {
      assert.equal((await fetch(url, {method: 'DELETE'})).status, 200);
    }
  };
  t.after(async () => { await reset(); await db.terminate(); await deleteApp(app); });
  await reset();
  const rules = await fetch(`http://${host}/emulator/v1/projects/${project}:securityRules`, {
    method: 'PUT', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({rules: {files: [{name: 'firestore.rules',
      content: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8')}]}}),
  });
  assert.equal(rules.status, 200);
  const identity = createProfileIdentity({firestore: db, auth, HttpsError, FieldValue});
  const submit = createAccessRequestSubmission({identity, HttpsError,
    storage: () => ({bucket: () => ({file: (name) => ({name, getMetadata: async () => [{
      size: '1234', contentType: 'application/pdf', metadata: {uploadedBy: name.split('/')[1]},
    }]})})}), getDownloadURL: async () => 'https://example.com/fictional-document'});
  const anonymous = async () => {
    const user = await auth.createUser({uid: `anonymous-${db.collection('accessRequests').doc().id}`});
    const now = Math.floor(Date.now() / 1000);
    const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
    // Unsigned tokens are accepted only by the emulators, as in the rules suite.
    // Explicit audience keeps this demo isolated from other local test projects.
    const idToken = `${encode({alg: 'none', typ: 'JWT'})}.${encode({sub: user.uid,
      user_id: user.uid, iss: `https://securetoken.google.com/${project}`, aud: project,
      iat: now, exp: now + 3600, auth_time: now,
      firebase: {sign_in_provider: 'anonymous'}})}.`;
    const token = await auth.verifyIdToken(idToken);
    return {uid: token.uid, token, idToken};
  };
  const payload = (caller, dni, extra = {}) => ({requestId: db.collection('accessRequests').doc().id,
    name: 'Fictional Applicant', dni, phone: '000000001', email: 'applicant@example.com',
    address: 'Fictional address', timeLivingHere: '1 a 5 años', reason: 'Local test',
    identityDocumentPath: `access_requests/${caller.uid}/identity/document.pdf`, ...extra});
  const profile = (dni, extra = {}) => ({nombre: 'Fictional Resident', dni, phone: '000000001',
    email: 'resident@example.com', address: 'Fictional address', timeLivingHere: '1 a 5 años',
    reason: 'Local test', role: 'vecino', approvalStatus: 'aprobado', ...extra});
  await db.doc('users/admin-demo').set(profile('00000009', {role: 'admin', email: 'admin@example.com'}));
  const source = fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8');
  const context = {exports: {}, onCall: (_, callback) => callback, region: 'local',
    communityId: 'fictional-community', communityName: 'MiComunidad', HttpsError, FieldValue,
    profileSnapshot, getFirestore: () => db, getAuth: () => auth, profileIdentity: () => identity,
    sendEmail: async () => true, console: {error: () => {}}};
  const guard = source.indexOf('async function requireAdmin');
  vm.runInNewContext(source.slice(guard, source.indexOf('function hash', guard)), context);
  const review = source.indexOf('exports.reviewAccessRequest =');
  vm.runInNewContext(source.slice(review, source.indexOf('exports.setUserRole =', review)), context);
  const approve = (requestId) => context.exports.reviewAccessRequest({auth: {uid: 'admin-demo'},
    data: {requestId, action: 'approve'}});
  let winner;

  for (const sameEmail of [true, false]) {
    await t.test(`concurrent anonymous submissions save exactly one request (same email: ${sameEmail})`, async () => {
      const a = await anonymous();
      const b = await anonymous();
      const dni = sameEmail ? '00000001' : '00000002';
      const inputs = [payload(a, dni, {email: sameEmail ? 'applicant@example.com' : 'first-dni@example.com'}),
        payload(b, dni, {email: sameEmail ? 'applicant@example.com' : 'other@example.com'})];
      const results = await Promise.allSettled([
        submit({auth: a, data: inputs[0]}), submit({auth: b, data: inputs[1]}),
      ]);
      assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
      assert.equal(results.find((r) => r.status === 'rejected').reason.code, 'already-exists');
      const stored = await db.collection('accessRequests').where('dni', '==', dni).get();
      assert.equal(stored.size, 1);
      assert.equal(stored.docs[0].data().status, 'pendiente');
      assert.equal((await db.collection('users').where('dni', '==', dni).get()).size, 0);
      if (sameEmail) {
        const index = results.findIndex((r) => r.status === 'fulfilled');
        winner = {caller: index === 0 ? a : b, input: inputs[index], ref: stored.docs[0].ref};
      }
    });
  }

  await t.test('replayed request is idempotent; direct client writes cannot bypass the callable', async () => {
    const original = (await winner.ref.get()).data();
    await Promise.all([submit({auth: winner.caller, data: winner.input}), submit({auth: winner.caller, data: winner.input})]);
    assert.deepEqual((await winner.ref.get()).data(), original);
    for (const uid of [winner.caller.uid, 'admin-demo']) {
      const now = Math.floor(Date.now() / 1000);
      const encode = (v) => Buffer.from(JSON.stringify(v)).toString('base64url');
      const token = uid === winner.caller.uid ? winner.caller.idToken :
        `${encode({alg: 'none', typ: 'JWT'})}.${encode({sub: uid, user_id: uid,
          iss: `https://securetoken.google.com/${project}`, aud: project, iat: now, exp: now + 3600,
          auth_time: now, firebase: {sign_in_provider: 'password'}})}.`;
      const response = await fetch(`${base}/accessRequests/direct-${uid}`, {method: 'PATCH',
        headers: {'Content-Type': 'application/json', Authorization: `Bearer ${token}`},
        body: JSON.stringify({fields: {dni: {stringValue: '00000001'}, status: {stringValue: 'pendiente'},
          applicantUid: {stringValue: uid}, phone: {stringValue: '000000001'},
          email: {stringValue: 'test@example.com'}, identityDocumentUrl: {stringValue: 'https://example.com/test'}}}),
      });
      assert.equal(response.status, 403);
    }
    const index = await db.collection('memberDniKeys').get();
    const denied = await fetch(`${base}/memberDniKeys/${index.docs[0].id}`, {
      headers: {Authorization: `Bearer ${winner.caller.idToken}`},
    });
    assert.equal(denied.status, 403);
  });

  await t.test('server-created application approves normally and a newer rejection cannot hide it', async () => {
    await approve(winner.ref.id);
    const approved = (await winner.ref.get()).data();
    const duplicate = {...approved, name: 'Rejected Fictional Applicant', status: 'rechazado',
      approvedUserId: null, createdAt: Timestamp.fromMillis(Date.now())};
    await db.doc('accessRequests/legacy-rejected').set(duplicate);
    const visible = (await identity.findRequestStatus('00000001')).request;
    assert.equal(visible.status, 'aprobado');
    assert.equal(visible.name, 'Fictional Applicant');
    assert.equal(visible.email, 'ap****@***.com');
    assert.equal((await db.collection('users').where('dni', '==', '00000001').get()).size, 1);
    assert.equal((await auth.getUser(approved.approvedUserId)).customClaims.approved, true);
    winner.uid = approved.approvedUserId;
  });

  await t.test('DNI correction preserves the original request and frees only the former number', async () => {
    const original = (await winner.ref.get()).data();
    await db.doc('reports/unchanged').set({createdBy: winner.uid, title: 'Fictional report'});
    await identity.updateOwnProfile(winner.uid, profile('00000003', {nombre: 'Corrected Resident', email: 'applicant@example.com'}));
    const visible = (await identity.findRequestStatus('00000003')).request;
    assert.equal(visible.status, 'aprobado');
    assert.equal(visible.name, 'Corrected Resident');
    assert.notEqual((await identity.findRequestStatus('00000001')).request.status, 'aprobado');
    const a = await anonymous();
    await submit({auth: a, data: payload(a, '00000001', {email: 'new@example.com'})});
    assert.equal((await identity.findRequestStatus('00000001')).request.status, 'pendiente');
    for (const key of ['name', 'dni', 'phone', 'email', 'address', 'timeLivingHere', 'reason']) {
      assert.equal((await winner.ref.get()).data()[key], original[key]);
    }
    assert.equal((await db.doc('reports/unchanged').get()).data().createdBy, winner.uid);
  });

  await t.test('withdrawal preserves corrected-DNI history and allows an independent reapplication', async () => {
    await context.exports.removeNeighbor({auth: {uid: 'admin-demo'}, data: {userId: winner.uid}});
    assert.equal((await identity.findRequestStatus('00000003')).request.status, 'retirado');
    await assert.rejects(auth.getUser(winner.uid), {code: 'auth/user-not-found'});
    const a = await anonymous();
    await submit({auth: a, data: payload(a, '00000003')});
    assert.equal((await identity.findRequestStatus('00000003')).request.status, 'pendiente');
    assert.equal((await winner.ref.get()).data().status, 'retirado');
    assert.equal((await db.doc('reports/unchanged').get()).data().createdBy, winner.uid);
  });

  await t.test('a profile correction and an anonymous submission cannot claim the same DNI', async () => {
    for (let n = 0; n < 4; n++) {
      const initial = String(100 + n * 2).padStart(8, '0');
      const target = String(101 + n * 2).padStart(8, '0');
      const uid = `race-resident-${n}`;
      const email = `race${n}@example.com`;
      await auth.createUser({uid, email});
      await db.doc(`users/${uid}`).set(profile(initial, {email}));
      const a = await anonymous();
      const results = await Promise.allSettled([
        identity.updateOwnProfile(uid, profile(target, {email})),
        submit({auth: a, data: payload(a, target, {email: `submission-race${n}@example.com`})}),
      ]);
      assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
      const members = await db.collection('users').where('dni', '==', target).get();
      const requests = await db.collection('accessRequests').where('dni', '==', target).get();
      assert.equal(members.size + requests.size, 1);
    }
  });

  await t.test('different DNIs and emails submit concurrently without blocking one another', async () => {
    const a = await anonymous();
    const b = await anonymous();
    await Promise.all([submit({auth: a, data: payload(a, '00000007', {email: 'independent-a@example.com'})}),
      submit({auth: b, data: payload(b, '00000008', {email: 'independent-b@example.com'})})]);
    for (const dni of ['00000007', '00000008']) {
      assert.equal((await db.collection('accessRequests').where('dni', '==', dni).get()).size, 1);
    }
  });

  await t.test('different DNIs cannot reserve the same normalized email concurrently', async () => {
    const a = await anonymous();
    const b = await anonymous();
    const inputs = [payload(a, '00000050', {email: ' Shared@Example.com '}),
      payload(b, '00000051', {email: 'shared@example.com'})];
    const results = await Promise.allSettled([submit({auth: a, data: inputs[0]}), submit({auth: b, data: inputs[1]})]);
    assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
    assert.equal(results.find(r => r.status === 'rejected').reason.code, 'already-exists');
    assert.equal((await db.collection('accessRequests').where('email', '==', 'shared@example.com').get()).size, 1);
    const {createHash} = require('node:crypto');
    const key = createHash('sha256').update('shared@example.com').digest('hex');
    const denied = await fetch(`${base}/memberEmailKeys/${key}`, {headers: {Authorization: `Bearer ${a.idToken}`}});
    assert.equal(denied.status, 403);
  });

  await t.test('profile email correction and submission share the email lock', async () => {
    for (let n = 0; n < 4; n++) {
      const uid = `email-race-${n}`, current = `old-email-${n}@example.com`, target = `target-email-${n}@example.com`;
      const dni = String(500 + n * 2).padStart(8, '0');
      await auth.createUser({uid, email: current});
      await db.doc(`users/${uid}`).set(profile(dni, {email: current}));
      const a = await anonymous();
      const otherDni = String(501 + n * 2).padStart(8, '0');
      const results = await Promise.allSettled([
        identity.updateOwnProfile(uid, profile(dni, {email: target})),
        submit({auth: a, data: payload(a, otherDni, {email: target})}),
      ]);
      assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
      assert.equal(results.find(r => r.status === 'rejected').reason.code, 'already-exists');
      const residents = await db.collection('users').where('email', '==', target).get();
      const applications = await db.collection('accessRequests').where('email', '==', target).get();
      assert.equal(residents.size + applications.size, 1);
      assert.equal((await auth.getUser(uid)).email, (await db.doc(`users/${uid}`).get()).data().email);
    }
  });
});
