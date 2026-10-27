// Fictional accounts and in-memory services only. No network or credentials.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {fixture, HttpsError} = require('./helpers/identity_fixture.cjs');
const source = fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8');
const conflictMessage = 'Ya existe una cuenta de Firebase Authentication con este correo. La solicitud requiere revisión y no se ha aprobado.';
const authError = code => Object.assign(new Error('Fictional Auth failure'), {code});
const applicant = (extra = {}) => ({name: 'Fictional Applicant', dni: '00000001', phone: '000000001',
  email: 'applicant@example.com', address: 'Fictional address', timeLivingHere: '1 a 5 años',
  reason: 'Local test', status: 'pendiente', ...extra});
const admin = {nombre: 'Fictional Admin', email: 'admin@example.com', role: 'admin', approvalStatus: 'aprobado'};

function setup({application = applicant(), members = [], accounts = [], failWrite = false} = {}) {
  const f = fixture({members: [['admin', {...admin}], ...members],
    requests: application ? [['pending', application]] : [], failWrite});
  const authAccounts = new Map(accounts.map(a => [a.uid, structuredClone(a)]));
  const calls = {create: [], claims: [], delete: [], reset: [], mail: []};
  let sequence = 0;
  const normalize = email => String(email).trim().toLowerCase();
  const auth = Object.assign(f.auth, {
    getUserByEmail: async email => {
      const account = [...authAccounts.values()].find(a => normalize(a.email) === normalize(email));
      if (!account) throw authError('auth/user-not-found');
      return structuredClone(account);
    },
    createUser: async values => {
      calls.create.push({...values});
      if ([...authAccounts.values()].some(a => normalize(a.email) === normalize(values.email))) {
        throw authError('auth/email-already-exists');
      }
      const account = {uid: `created-${++sequence}`, ...values, email: normalize(values.email)};
      authAccounts.set(account.uid, account);
      return {...account};
    },
    setCustomUserClaims: async (uid, claims) => {
      calls.claims.push({uid, ...claims});
      authAccounts.get(uid).customClaims = {...claims};
    },
    deleteUser: async uid => {calls.delete.push(uid); authAccounts.delete(uid);},
    generatePasswordResetLink: async email => {calls.reset.push(email); return 'https://example.com/fictional-reset';},
  });
  // Add the direct update used by rejection, keeping the shared transaction fake intact.
  const collection = f.db.collection;
  f.db.collection = name => {
    const q = collection(name), doc = q.doc;
    q.doc = id => ({...doc(id), update: async values => {
      f.data[name].set(id, {...f.data[name].get(id), ...values});
    }});
    return q;
  };
  const context = {exports: {}, onCall: (_, callback) => callback, region: 'local', HttpsError,
    communityId: 'fictional-community', communityName: 'MiComunidad',
    getAuth: () => auth, getFirestore: () => f.db, profileIdentity: () => f.identity,
    FieldValue: {serverTimestamp: () => 'server-time'},
    sendEmail: async values => {calls.mail.push({...values}); return true;}};
  vm.runInNewContext(source.slice(source.indexOf('async function requireAdmin'), source.indexOf('async function sendEmail')), context);
  vm.runInNewContext(source.slice(source.indexOf('exports.reviewAccessRequest ='), source.indexOf('exports.removeNeighbor =')), context);
  const review = (data = {}, caller = {uid: 'admin'}) => context.exports.reviewAccessRequest({auth: caller,
    data: {requestId: 'pending', action: 'approve', ...data}});
  const snapshot = () => JSON.stringify({data: Object.fromEntries(Object.entries(f.data).map(([k, v]) => [k, [...v]])),
    accounts: [...authAccounts]});
  return {...f, auth, authAccounts, calls, review, snapshot};
}

function noApproval(f) {
  assert.equal(f.calls.claims.length, 0);
  assert.equal(f.calls.reset.length, 0);
  assert.equal(f.calls.mail.length, 0);
  assert.equal(f.calls.delete.length, 0);
}

for (const extra of [{}, {emailVerified: true}, {disabled: true}, {email: 'Applicant@Example.COM'}]) {
  test(`Auth-only preexisting account is never approved or changed: ${JSON.stringify(extra)}`, async () => {
    const f = setup({accounts: [{uid: 'external', email: 'applicant@example.com',
      password: 'fictional-unchanged-password', customClaims: {customFlag: true}, ...extra}]});
    const before = f.snapshot();
    await assert.rejects(f.review(), {code: 'already-exists', message: conflictMessage});
    assert.equal(f.snapshot(), before);
    assert.equal(f.data.users.has('external'), false);
    assert.equal(f.calls.create.length, 0);
    noApproval(f);
  });
}

test('account created externally after a valid submission cannot receive access', async () => {
  const f = setup({application: null});
  await f.identity.submitAccessRequest('fictional-anonymous', {
    ...applicant(), requestId: 'pending', identityDocumentPath: 'fictional/document.pdf',
    identityDocumentUrl: 'https://example.com/fictional-document',
  });
  f.authAccounts.set('external', {uid: 'external', email: 'applicant@example.com', password: 'fictional-password'});
  const before = f.snapshot();
  await assert.rejects(f.review(), {code: 'already-exists', message: conflictMessage});
  assert.equal(f.snapshot(), before);
  assert.equal(f.data.accessRequests.get('pending').status, 'pendiente');
  assert.equal(f.data.users.has('external'), false);
  noApproval(f);
});

for (const status of ['pendiente', 'rechazado']) {
  test(`normal ${status} approval creates a new account/profile, links request and preserves existing users`, async () => {
    const member = {nombre: 'Fictional Resident', dni: '00000002', email: 'resident@example.com',
      role: 'vecino', approvalStatus: 'aprobado'};
    const existingAccount = {uid: 'resident', email: member.email, password: 'fictional-password',
      customClaims: {approved: true, role: 'vecino', unchanged: true}};
    const f = setup({application: applicant({status}), members: [['resident', member]], accounts: [existingAccount]});
    const result = await f.review();
    assert.equal(result.success, true);
    assert.equal(f.calls.create.length, 1);
    const uid = f.data.accessRequests.get('pending').approvedUserId;
    assert.equal(uid, 'created-1');
    assert.equal(f.data.accessRequests.get('pending').status, 'aprobado');
    assert.equal(f.data.users.get(uid).role, 'vecino');
    assert.equal(f.data.users.get(uid).approvalStatus, 'aprobado');
    assert.equal(f.data.memberDniKeys.size, 1);
    assert.equal(f.data.memberEmailKeys.size, 1);
    assert.deepEqual(f.authAccounts.get(uid).customClaims, {approved: true, role: 'vecino'});
    assert.equal(f.calls.reset.length, 1);
    assert.equal(f.calls.mail.length, 1);
    assert.deepEqual(f.data.users.get('resident'), member);
    assert.deepEqual(f.authAccounts.get('resident'), existingAccount);
    const after = f.snapshot();
    await assert.rejects(f.review(), {code: 'failed-precondition'});
    assert.equal(f.snapshot(), after);
    assert.equal(f.calls.create.length, 1);
  });
}

test('preexisting approved account is preserved instead of reused or assigned new claims', async () => {
  const member = {...admin, email: 'applicant@example.com'};
  const f = setup({members: [['existing-admin', member]], accounts: [{uid: 'existing-admin',
    email: member.email, customClaims: {approved: true, role: 'admin'}}]});
  const before = f.snapshot();
  await assert.rejects(f.review(), {code: 'already-exists', message: conflictMessage});
  assert.equal(f.snapshot(), before);
  noApproval(f);
});

test('account created between lookup and createUser also blocks approval, without deleting that account', async () => {
  const f = setup(), create = f.auth.createUser;
  f.auth.createUser = async values => {
    f.authAccounts.set('racing-external', {uid: 'racing-external', email: values.email, password: 'fictional-password'});
    return create(values);
  };
  const beforeData = JSON.stringify([...f.data.accessRequests]);
  await assert.rejects(f.review(), {code: 'already-exists', message: conflictMessage});
  assert.equal(JSON.stringify([...f.data.accessRequests]), beforeData);
  assert.equal(f.data.users.size, 1);
  assert.equal(f.authAccounts.size, 1);
  assert.equal(f.authAccounts.has('racing-external'), true);
  noApproval(f);
});

test('simultaneous admin approvals create exactly one approved account', async () => {
  const f = setup();
  const result = await Promise.allSettled([f.review(), f.review()]);
  assert.equal(result.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal(result.find(r => r.status === 'rejected').reason.code, 'already-exists');
  assert.equal(f.authAccounts.size, 1);
  assert.equal(f.data.users.size, 2);
  assert.equal(f.calls.claims.length, 1);
  assert.equal(f.calls.reset.length, 1);
  assert.equal(f.calls.delete.length, 0);
});

test('unknown Auth lookup errors never create, approve, or send an email', async () => {
  const f = setup(), before = f.snapshot();
  f.auth.getUserByEmail = async () => {throw authError('auth/internal-error');};
  await assert.rejects(f.review(), {code: 'auth/internal-error'});
  assert.equal(f.snapshot(), before);
  assert.equal(f.calls.create.length, 0);
  noApproval(f);
});

test('account creation failures leave the request unchanged', async () => {
  const f = setup(), before = f.snapshot();
  f.auth.createUser = async () => {throw authError('auth/internal-error');};
  await assert.rejects(f.review(), {code: 'auth/internal-error'});
  assert.equal(f.snapshot(), before);
  noApproval(f);
});

test('failed Firestore commit cleans up only the account just created by this approval', async () => {
  const external = {uid: 'unrelated', email: 'unrelated@example.com'};
  const f = setup({failWrite: true, accounts: [external]}), before = f.snapshot();
  await assert.rejects(f.review(), /Simulated Firestore failure/);
  assert.equal(f.snapshot(), before);
  assert.deepEqual(f.calls.delete, ['created-1']);
  assert.equal(f.calls.claims.length, 0);
  assert.equal(f.calls.reset.length, 0);
  assert.equal(f.calls.mail.length, 0);
});

test('rejection is still allowed without changing a preexisting Auth account', async () => {
  const external = {uid: 'external', email: 'applicant@example.com', password: 'fictional-password'};
  const f = setup({accounts: [external]});
  const result = await f.review({action: 'reject', reason: 'Fictional reason'});
  assert.equal(result.success, true);
  assert.equal(f.data.accessRequests.get('pending').status, 'rechazado');
  assert.equal(f.data.accessRequests.get('pending').rejectionReason, 'Fictional reason');
  assert.deepEqual(f.authAccounts.get('external'), external);
  assert.equal(f.data.users.size, 1);
  assert.equal(f.calls.create.length, 0);
  assert.equal(f.calls.claims.length, 0);
  assert.equal(f.calls.reset.length, 0);
  assert.equal(f.calls.delete.length, 0);
});

test('unauthenticated, unapproved and normal users cannot approve', async () => {
  const f = setup({members: [['resident', {role: 'vecino', approvalStatus: 'aprobado'}],
    ['former-admin', {role: 'admin', approvalStatus: 'retirado'}]]});
  const before = f.snapshot();
  await assert.rejects(f.review({}, null), {code: 'unauthenticated'});
  for (const uid of ['resident', 'former-admin', 'anonymous']) {
    await assert.rejects(f.review({}, {uid}), {code: 'permission-denied'});
  }
  assert.equal(f.snapshot(), before);
  assert.equal(f.calls.create.length, 0);
  noApproval(f);
});

test('missing requests, unsupported actions and reviewed requests cannot create accounts', async () => {
  const f = setup(), before = f.snapshot();
  await assert.rejects(f.review({requestId: 'missing'}), {code: 'not-found'});
  await assert.rejects(f.review({action: 'unsupported'}), {code: 'invalid-argument'});
  assert.equal(f.snapshot(), before);
  for (const status of ['aprobado', 'retirado']) {
    f.data.accessRequests.get('pending').status = status;
    await assert.rejects(f.review(), {code: 'failed-precondition'});
  }
  assert.equal(f.calls.create.length, 0);
  noApproval(f);
});
