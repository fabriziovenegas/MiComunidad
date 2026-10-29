// Official local Authentication/Firestore emulators and fictional identities only.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const project = 'demo-micomunidad-approval-guard';
const host = process.env.FIRESTORE_EMULATOR_HOST;
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
for (const value of [host, authHost]) {
  if (value && !/^127\.0\.0\.1:\d+$/.test(value)) throw Error('Loopback emulators required');
}

test('approval never grants access to a preexisting Auth account', {skip: !host || !authHost}, async t => {
  const {initializeApp, deleteApp} = require('firebase-admin/app');
  const {getFirestore, FieldValue} = require('firebase-admin/firestore');
  const {getAuth} = require('firebase-admin/auth');
  const {HttpsError} = require('firebase-functions/v2/https');
  const {createProfileIdentity} = require('../profile_identity');
  const app = initializeApp({projectId: project}, 'approval-guard-local');
  const db = getFirestore(app), auth = getAuth(app);
  const source = fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8');
  const calls = {mail: 0, reset: 0};
  const authProxy = Object.create(auth);
  authProxy.generatePasswordResetLink = async email => {
    calls.reset++;
    return auth.generatePasswordResetLink(email);
  };
  const identity = createProfileIdentity({firestore: db, auth, HttpsError, FieldValue});
  // The callback is evaluated in a VM realm; the official SDK requires a
  // native Promise from its own realm for transaction callbacks.
  const firestoreFacade = {
    collection: (...args) => db.collection(...args),
    runTransaction: callback => db.runTransaction(transaction => Promise.resolve(callback(transaction))),
  };
  const context = {exports: {}, onCall: (_, callback) => callback, region: 'local', HttpsError,
    communityId: 'fictional-community', communityName: 'MiComunidad', FieldValue,
    getFirestore: () => firestoreFacade, getAuth: () => authProxy, profileIdentity: () => identity,
    sendEmail: async () => {calls.mail++; return true;}};
  vm.runInNewContext(source.slice(source.indexOf('async function requireAdmin'), source.indexOf('async function sendEmail')), context);
  vm.runInNewContext(source.slice(source.indexOf('exports.reviewAccessRequest ='), source.indexOf('exports.removeNeighbor =')), context);
  const review = id => context.exports.reviewAccessRequest({auth: {uid: 'admin'}, data: {requestId: id, action: 'approve'}});
  const reset = async () => {
    for (const url of [`http://${host}/emulator/v1/projects/${project}/databases/(default)/documents`,
      `http://${authHost}/emulator/v1/projects/${project}/accounts`]) {
      assert.equal((await fetch(url, {method: 'DELETE'})).status, 200);
    }
  };
  t.after(async () => {await reset(); await db.terminate(); await deleteApp(app);});
  await reset();
  const rules = await fetch(`http://${host}/emulator/v1/projects/${project}:securityRules`, {
    method: 'PUT', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({rules: {files: [{name: 'firestore.rules',
      content: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8')}]}}),
  });
  assert.equal(rules.status, 200);
  await auth.createUser({uid: 'admin', email: 'admin@example.com'});
  await auth.setCustomUserClaims('admin', {approved: true, role: 'admin'});
  const adminProfile = {nombre: 'Fictional Admin', email: 'admin@example.com', role: 'admin', approvalStatus: 'aprobado'};
  await db.doc('users/admin').set(adminProfile);
  await auth.createUser({uid: 'existing-resident', email: 'resident@example.com', password: 'fictional-password'});
  await auth.setCustomUserClaims('existing-resident', {approved: true, role: 'vecino', customFlag: true});
  const residentProfile = {nombre: 'Fictional Resident', email: 'resident@example.com',
    dni: '00000009', role: 'vecino', approvalStatus: 'aprobado'};
  await db.doc('users/existing-resident').set(residentProfile);
  const existingResident = (await auth.getUser('existing-resident')).toJSON();

  async function submit(id, dni, email) {
    await identity.submitAccessRequest(`anonymous-${id}`, {requestId: id, name: 'Fictional Applicant', dni,
      email, phone: '000000001', address: 'Fictional address', timeLivingHere: '1 a 5 años',
      reason: 'Local test', identityDocumentPath: `fictional/${id}.pdf`,
      identityDocumentUrl: 'https://example.com/fictional-document'});
  }
  async function externalSignup(email) {
    // Use this test's explicit project. The Auth emulator routes unscoped client
    // API keys to its CLI default project, which may be a different demo here.
    // Actual unauthenticated REST sign-up is covered by backend_security's
    // callable HTTP test in the CLI default demo project.
    const account = await auth.createUser({email, password: 'fictional-password'});
    const now = Math.floor(Date.now() / 1000);
    const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
    const idToken = `${encode({alg: 'none', typ: 'JWT'})}.${encode({sub: account.uid,
      user_id: account.uid, aud: project, iss: `https://securetoken.google.com/${project}`,
      iat: now, exp: now + 3600, firebase: {sign_in_provider: 'password'}})}.`;
    return {localId: account.uid, idToken};
  }

  await t.test('direct external signup after submission is blocked at approval and still cannot read protected data', async () => {
    await submit('pending-external', '00000001', 'external@example.com');
    const external = await externalSignup('external@example.com');
    const before = (await auth.getUser(external.localId)).toJSON();
    const original = (await db.doc('accessRequests/pending-external').get()).data();
    const keysBefore = await db.collection('memberEmailKeys').get();
    await assert.rejects(review('pending-external'), error => error.code === 'already-exists' &&
      /Authentication.*requiere revisión.*no se ha aprobado/.test(error.message));
    assert.deepEqual((await auth.getUser(external.localId)).toJSON(), before);
    assert.equal((await db.doc(`users/${external.localId}`).get()).exists, false);
    assert.deepEqual((await db.doc('accessRequests/pending-external').get()).data(), original);
    assert.deepEqual((await db.collection('memberEmailKeys').get()).docs.map(d => d.data()), keysBefore.docs.map(d => d.data()));
    assert.equal(calls.reset, 0);
    assert.equal(calls.mail, 0);
    await db.doc('reports/fictional-protected').set({title: 'Fictional report', moderationStatus: 'aprobado'});
    const base = `http://${host}/v1/projects/${project}/databases/(default)/documents`;
    const response = await fetch(`${base}/reports/fictional-protected`, {
      headers: {Authorization: `Bearer ${external.idToken}`},
    });
    assert.equal(response.status, 403);
    const escalation = await fetch(`${base}/users/${external.localId}`, {
      method: 'PATCH', headers: {Authorization: `Bearer ${external.idToken}`, 'Content-Type': 'application/json'},
      body: JSON.stringify({fields: {role: {stringValue: 'admin'}, approvalStatus: {stringValue: 'aprobado'}}}),
    });
    assert.equal(escalation.status, 403);
  });

  for (const [status, dni] of [['pendiente', '00000002'], ['rechazado', '00000003']]) {
    await t.test(`only pending requests can be approved: ${status}`, async () => {
      const id = `normal-${status}`, email = `${id}@example.com`;
      await submit(id, dni, email);
      if (status === 'rechazado') {
        await db.doc(`accessRequests/${id}`).update({status, rejectionReason: 'Documento ilegible.'});
        const before = (await db.doc(`accessRequests/${id}`).get()).data();
        await assert.rejects(review(id), {code: 'failed-precondition'});
        await assert.rejects(auth.getUserByEmail(email), {code: 'auth/user-not-found'});
        assert.deepEqual((await db.doc(`accessRequests/${id}`).get()).data(), before);
        assert.equal((await db.collection('users').where('email', '==', email).get()).empty, true);
        return;
      }
      const result = await review(id);
      assert.equal(result.success, true);
      const request = (await db.doc(`accessRequests/${id}`).get()).data();
      const account = await auth.getUserByEmail(email);
      const profile = (await db.doc(`users/${account.uid}`).get()).data();
      assert.equal(request.status, 'aprobado');
      assert.equal(request.approvedUserId, account.uid);
      assert.equal(profile.approvalStatus, 'aprobado');
      assert.equal(profile.role, 'vecino');
      assert.deepEqual(account.customClaims, {approved: true, role: 'vecino'});
      await assert.rejects(review(id), {code: 'failed-precondition'});
    });
  }

  await t.test('an external account created between lookup and createUser is also blocked', async () => {
    await submit('race', '00000004', 'racing-external@example.com');
    let external;
    authProxy.createUser = async values => {
      external = await externalSignup(values.email);
      return auth.createUser(values);
    };
    try {
      await assert.rejects(review('race'), {code: 'already-exists'});
    } finally {
      delete authProxy.createUser;
    }
    assert.equal((await db.doc(`users/${external.localId}`).get()).exists, false);
    assert.equal((await db.doc('accessRequests/race').get()).data().status, 'pendiente');
    assert.deepEqual((await auth.getUser(external.localId)).customClaims || {}, {});
    assert.equal(calls.reset, 1);
    assert.equal(calls.mail, 1);
  });

  await t.test('two simultaneous approvals create one account and one approved profile', async () => {
    await submit('concurrent', '00000005', 'concurrent@example.com');
    const result = await Promise.allSettled([review('concurrent'), review('concurrent')]);
    assert.equal(result.filter(r => r.status === 'fulfilled').length, 1);
    assert.equal(result.find(r => r.status === 'rejected').reason.code, 'already-exists');
    assert.equal((await db.collection('users').where('email', '==', 'concurrent@example.com').get()).size, 1);
    const account = await auth.getUserByEmail('concurrent@example.com');
    assert.equal((await db.doc('accessRequests/concurrent').get()).data().approvedUserId, account.uid);
    assert.deepEqual(account.customClaims, {approved: true, role: 'vecino'});
  });

  await t.test('already-approved users and administrators remain unchanged', async () => {
    assert.deepEqual((await db.doc('users/admin').get()).data(), adminProfile);
    assert.deepEqual((await db.doc('users/existing-resident').get()).data(), residentProfile);
    assert.deepEqual((await auth.getUser('existing-resident')).toJSON(), existingResident);
    assert.deepEqual((await auth.getUser('admin')).customClaims, {approved: true, role: 'admin'});
  });

  await t.test('rejection during approval prevents an approved profile and removes the new Auth account', async () => {
    await submit('rejected-during-approval', '00000006', 'rejected-during-approval@example.com');
    authProxy.createUser = async values => {
      const account = await auth.createUser(values);
      await context.exports.reviewAccessRequest({auth: {uid: 'admin'}, data: {
        requestId: 'rejected-during-approval', action: 'reject', reason: 'Documento ilegible.',
      }});
      return account;
    };
    try {
      await assert.rejects(review('rejected-during-approval'), {code: 'failed-precondition'});
    } finally {
      delete authProxy.createUser;
    }
    const request = (await db.doc('accessRequests/rejected-during-approval').get()).data();
    assert.equal(request.status, 'rechazado');
    assert.equal(request.rejectionReason, 'Documento ilegible.');
    assert.equal(request.approvedUserId, undefined);
    assert.equal((await db.collection('users').where('email', '==', 'rejected-during-approval@example.com').get()).empty, true);
    await assert.rejects(auth.getUserByEmail('rejected-during-approval@example.com'), {code: 'auth/user-not-found'});
  });
});
