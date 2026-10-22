// Fictional identities only; no network or real credentials.
const test = require('node:test');
const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const {fixture} = require('./helpers/identity_fixture.cjs');
const key = value => createHash('sha256').update(value).digest('hex');
const application = (extra = {}) => ({requestId: 'a', name: 'Fictional Applicant',
  dni: '00000001', phone: '000000001', email: 'applicant@example.com', address: 'Fictional address',
  timeLivingHere: '1 a 5 años', reason: 'Local test', identityDocumentPath: 'fictional/document.pdf',
  identityDocumentUrl: 'https://example.com/document', ...extra});
const profile = (extra = {}) => ({nombre: 'Fictional Resident', dni: '00000003', phone: '000000001',
  email: 'resident@example.com', address: 'Fictional address', timeLivingHere: '1 a 5 años',
  reason: 'Local test', role: 'vecino', approvalStatus: 'aprobado', ...extra});

test('same email with different DNIs has one winner, including casing and whitespace', async () => {
  const f = fixture();
  const result = await Promise.allSettled([
    f.identity.submitAccessRequest('anon-a', application({email: ' Applicant@Example.com '})),
    f.identity.submitAccessRequest('anon-b', application({requestId: 'b', dni: '00000002'})),
  ]);
  assert.equal(result.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal(result.find(r => r.status === 'rejected').reason.code, 'already-exists');
  assert.equal(f.data.accessRequests.size, 1);
  assert.equal(f.data.memberEmailKeys.size, 1);
  assert.equal([...f.data.accessRequests.values()][0].email, 'applicant@example.com');
});

test('legacy pending email is blocked without a key, irrespective of DNI or case', async () => {
  const f = fixture({requests: [['legacy', {...application(), email: ' Applicant@Example.COM ', status: 'pendiente'}]]});
  await assert.rejects(f.identity.submitAccessRequest('anon-b', application({dni: '00000002'})), {code: 'already-exists'});
  assert.equal(f.data.accessRequests.size, 1);
});

test('current accounts block an email even without keys, applications or a matching DNI', async () => {
  for (const email of ['applicant@example.com', 'Applicant@Example.COM']) {
    const f = fixture({members: [['resident', profile({email})]]});
    await assert.rejects(f.identity.submitAccessRequest('anon', application()), {code: 'already-exists'});
    assert.equal(f.data.accessRequests.size, 0);
  }
  const f = fixture();
  f.auth.getUserByEmail = async () => ({uid: 'auth-only-account'});
  await assert.rejects(f.identity.submitAccessRequest('anon', application()), {code: 'already-exists'});
});

test('rejected and withdrawn histories release email unless another pending request or account holds it', async () => {
  for (const status of ['rechazado', 'retirado']) {
    const f = fixture();
    await f.identity.submitAccessRequest('anon-a', application());
    f.data.accessRequests.get('a').status = status;
    const original = {...f.data.accessRequests.get('a')};
    await f.identity.submitAccessRequest('anon-b', application({requestId: 'b', dni: '00000002'}));
    assert.deepEqual(f.data.accessRequests.get('a'), original);
    assert.equal(f.data.memberEmailKeys.get(key('applicant@example.com')).requestId, 'b');
    await assert.rejects(f.identity.submitAccessRequest('anon-c', application({requestId: 'c', dni: '00000004'})), {code: 'already-exists'});
  }
});

test('approval, email correction and withdrawal transfer and release email keys without rewriting history', async () => {
  const f = fixture();
  await f.identity.submitAccessRequest('anon', application());
  await f.identity.saveApprovedProfile(f.db.collection('accessRequests').doc('a'), 'resident',
    profile({dni: '00000001', email: 'applicant@example.com'}), {status: 'aprobado'});
  assert.deepEqual(f.data.memberEmailKeys.get(key('applicant@example.com')), {userId: 'resident'});
  await f.identity.updateOwnProfile('resident', profile({dni: '00000001', email: 'corrected@example.com'}));
  assert.equal(f.data.memberEmailKeys.has(key('applicant@example.com')), false);
  assert.equal(f.data.accessRequests.get('a').email, 'applicant@example.com');
  assert.equal(f.data.accessRequests.get('a').currentProfile.email, 'corrected@example.com');
  await f.identity.submitAccessRequest('another', application({requestId: 'b', dni: '00000002'}));
  await assert.rejects(f.identity.submitAccessRequest('third', application({requestId: 'c', dni: '00000004', email: 'corrected@example.com'})), {code: 'already-exists'});
  await f.identity.deleteMemberProfile('resident', profile({dni: '00000001', email: 'corrected@example.com'}));
  assert.equal(f.data.memberEmailKeys.has(key('corrected@example.com')), false);
  await f.identity.submitAccessRequest('third', application({requestId: 'c', dni: '00000004', email: 'corrected@example.com'}));
});

test('profile cannot take a pending email; older duplicate applications cannot both be approved', async () => {
  const f = fixture({members: [['resident', profile()]], requests: [['pending', {...application(), status: 'pendiente'}]]});
  await assert.rejects(f.identity.updateOwnProfile('resident', profile({email: 'applicant@example.com'})), {code: 'already-exists'});
  assert.equal(f.authWrites.length, 0);
  f.data.accessRequests.set('duplicate', {...application(), dni: '00000002', status: 'pendiente'});
  await assert.rejects(f.identity.saveApprovedProfile(f.db.collection('accessRequests').doc('pending'), 'new-resident',
    profile({dni: '00000001', email: 'applicant@example.com'}), {status: 'aprobado'}), {code: 'already-exists'});
  assert.equal(f.data.users.size, 1);
});

test('failed commits do not leave email reservations and unknown Auth errors fail closed', async () => {
  const f = fixture({failWrite: true});
  await assert.rejects(f.identity.submitAccessRequest('anon', application()), /Simulated Firestore failure/);
  assert.equal(f.data.memberEmailKeys.size, 0);
  const g = fixture();
  g.auth.getUserByEmail = async () => {throw Object.assign(new Error('Auth unavailable'), {code: 'auth/internal-error'});};
  await assert.rejects(g.identity.submitAccessRequest('anon', application()), {code: 'auth/internal-error'});
  assert.equal(g.data.accessRequests.size, 0);
});
