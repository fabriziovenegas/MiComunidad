// Fictional profiles only; this suite never contacts Firebase.
const test = require('node:test');
const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const {fixture} = require('./helpers/identity_fixture.cjs');

const profile = (extra = {}) => ({nombre: 'Demo Resident', dni: '00000001', phone: '000000001',
  email: 'resident@example.com', address: 'Demo address', timeLivingHere: '1 a 5 años',
  reason: 'Fictional registration', role: 'vecino', approvalStatus: 'aprobado', ...extra});
const application = (extra = {}) => ({name: 'Original Resident', dni: '00000001',
  email: 'original@example.com', phone: '000000001', address: 'Original demo address',
  timeLivingHere: 'Menos de 1 año', reason: 'Original fictional reason',
  status: 'aprobado', approvedUserId: 'resident-a', identityDocumentPath: 'demo/document', ...extra});
const changed = (extra = {}) => ({nombre: 'Updated Resident', dni: '00000002', phone: '000000002',
  email: 'updated@example.com', address: 'Updated demo address', timeLivingHere: '5 a 10 años',
  reason: 'Corrected fictional reason', ...extra});
const setup = (options = {}) => fixture({members: [['resident-a', profile()]],
  requests: [['request-a', application()]], ...options});
const key = (dni) => createHash('sha256').update(dni).digest('hex');

test('a legacy profile without community fields can still use the older four-field update', async () => {
  const previous = profile();
  for (const field of ['address', 'timeLivingHere', 'reason']) delete previous[field];
  const f = fixture({members: [['resident-a', previous]]});
  await f.identity.updateOwnProfile('resident-a', {nombre: previous.nombre, dni: previous.dni,
    phone: previous.phone, email: previous.email});
  assert.equal(f.data.users.get('resident-a').role, 'vecino');
  assert.equal(f.data.users.get('resident-a').dni, previous.dni);
});

test('a profile cannot introduce a residence dropdown value the app does not offer', async () => {
  const f = setup();
  await assert.rejects(f.identity.updateOwnProfile('resident-a', changed({timeLivingHere: 'invented'})), {code: 'invalid-argument'});
  assert.equal(f.authWrites.length, 0);
  assert.deepEqual(f.data.users.get('resident-a'), profile());
});

test('all seven fields save together; original request and ownership remain unchanged', async () => {
  const f = setup();
  const original = {...f.data.accessRequests.get('request-a')};
  await f.identity.updateOwnProfile('resident-a', changed());
  const stored = f.data.users.get('resident-a');
  for (const [field, value] of Object.entries(changed())) assert.equal(stored[field], value);
  assert.equal(stored.role, 'vecino');
  assert.equal(stored.approvalStatus, 'aprobado');
  const request = f.data.accessRequests.get('request-a');
  for (const [field, value] of Object.entries(original)) assert.equal(request[field], value);
  assert.equal(request.lookupDni, '00000002');
  assert.equal(request.currentProfile.name, 'Updated Resident');
  assert.equal(request.currentProfile.reason, 'Corrected fictional reason');
  assert.equal((await f.identity.findRequestStatus('00000001')).request, null);
  const result = (await f.identity.findRequestStatus('00000002')).request;
  assert.equal(Object.hasOwn(result, 'name'), false);
  assert.equal(result.email, 'up****d@example.com');
  assert.equal(result.status, 'aprobado');
  for (const field of ['dni', 'phone', 'address', 'reason', 'approvedUserId', 'currentProfile']) {
    assert.equal(Object.hasOwn(result, field), false);
  }
  assert.deepEqual(Object.keys(f.data), ['users', 'accessRequests', 'memberDniKeys', 'memberEmailKeys']);
});

test('a second DNI correction does not leave a working old lookup', async () => {
  const f = setup();
  await f.identity.updateOwnProfile('resident-a', changed());
  await f.identity.updateOwnProfile('resident-a', changed({dni: '00000003'}));
  assert.equal((await f.identity.findRequestStatus('00000001')).request, null);
  assert.equal((await f.identity.findRequestStatus('00000002')).request, null);
  assert.equal((await f.identity.findRequestStatus('00000003')).request.status, 'aprobado');
  assert.equal(f.data.memberDniKeys.has(key('00000002')), false);
  assert.equal(f.data.memberDniKeys.get(key('00000003')).userId, 'resident-a');
});

test('lookup uses a profile corrected before this change without rewriting the original request', async () => {
  const f = setup({members: [['resident-a', profile({dni: '00000002'})]]});
  assert.equal((await f.identity.findRequestStatus('00000001')).request, null);
  assert.equal((await f.identity.findRequestStatus('00000002')).request.email, 're*****t@example.com');
  assert.equal(f.data.accessRequests.get('request-a').dni, '00000001');
  assert.equal(f.data.accessRequests.get('request-a').lookupDni, undefined);
});

test('pending and rejected requests use their submitted data, not injected current fields', async () => {
  for (const status of ['pendiente', 'rechazado']) {
    const f = setup({members: [], requests: [['r', application({status, approvedUserId: null,
      lookupDni: '00000002', currentProfile: {name: 'Injected', dni: '00000002'}})]]});
    assert.equal((await f.identity.findRequestStatus('00000001')).request.email, 'or*****l@example.com');
    assert.equal((await f.identity.findRequestStatus('00000002')).request, null);
  }
});

test('DNI held by another profile or pending request is rejected before any change', async () => {
  for (const extra of [
    {members: [['resident-a', profile()], ['resident-b', profile({dni: '00000002'})]]},
    {requests: [['request-a', application()], ['pending', application({status: 'pendiente', approvedUserId: null, dni: '00000002'})]]},
  ]) {
    const f = setup(extra);
    await assert.rejects(f.identity.updateOwnProfile('resident-a', changed()), {code: 'already-exists'});
    assert.equal(f.data.users.get('resident-a').dni, '00000001');
    assert.equal(f.authWrites.length, 0);
  }
});

test('retired and rejected old applications do not reserve a DNI forever', async () => {
  for (const status of ['retirado', 'rechazado', 'aprobado']) {
    const f = setup({requests: [['request-a', application()], ['old', application({
      dni: '00000002', status, approvedUserId: 'deleted-account',
    })]]});
    await f.identity.updateOwnProfile('resident-a', changed());
    assert.equal(f.data.users.get('resident-a').dni, '00000002');
    assert.equal(f.data.accessRequests.get('old').approvedUserId, 'deleted-account');
  }
});

test('an independent request can still be found using the former DNI', async () => {
  const f = setup({requests: [['request-a', application()], ['independent', application({
    approvedUserId: null, status: 'pendiente', name: 'Another Demo Resident',
  })]]});
  await f.identity.updateOwnProfile('resident-a', changed());
  const result = (await f.identity.findRequestStatus('00000001')).request;
  assert.equal(Object.hasOwn(result, 'name'), false);
  assert.equal(result.status, 'pendiente');
});

test('legacy unlinked approval is linked only to an unambiguous account', async () => {
  const f = setup({requests: [['request-a', application({approvedUserId: null, email: 'resident@example.com'})]]});
  await f.identity.updateOwnProfile('resident-a', changed());
  assert.equal(f.data.accessRequests.get('request-a').approvedUserId, 'resident-a');
  assert.equal((await f.identity.findRequestStatus('00000002')).request.status, 'aprobado');
});

test('an unlinked historical application with a different email is not claimed', async () => {
  const f = setup({requests: [['request-a', application({approvedUserId: null})]]});
  await f.identity.updateOwnProfile('resident-a', changed());
  assert.equal(f.data.accessRequests.get('request-a').approvedUserId, null);
  assert.equal((await f.identity.findRequestStatus('00000002')).request, null);
});

test('a pending request cannot bypass the conflict check by injecting an owner UID', async () => {
  const f = setup({requests: [['request-a', application()], ['pending', application({
    status: 'pendiente', dni: '00000002', approvedUserId: 'resident-a',
  })]]});
  await assert.rejects(f.identity.updateOwnProfile('resident-a', changed()), {code: 'already-exists'});
});

test('a deleted application is not recreated and an unrelated UID is never relinked', async () => {
  for (const requests of [[], [['request-a', application({approvedUserId: 'another-account'})]]]) {
    const f = setup({requests});
    await f.identity.updateOwnProfile('resident-a', changed());
    assert.equal(f.data.accessRequests.size, requests.length);
    assert.equal((await f.identity.findRequestStatus('00000002')).request, null);
  }
});

test('older clients preserve omitted community fields and invalid data changes nothing', async () => {
  const f = setup();
  await f.identity.updateOwnProfile('resident-a', {nombre: 'Demo Resident', dni: '00000002',
    phone: '000000001', email: 'resident@example.com'});
  assert.equal(f.data.users.get('resident-a').address, 'Demo address');
  for (const patch of [{dni: 'invalid'}, {phone: 'short'}, {email: 'invalid'}, {nombre: ' '},
    {address: ''}, {address: 'x'.repeat(301)}, {reason: 'x'.repeat(1001)}, {timeLivingHere: ''}]) {
    await assert.rejects(f.identity.updateOwnProfile('resident-a', changed(patch)), {code: 'invalid-argument'});
    assert.equal(f.data.users.get('resident-a').dni, '00000002');
  }
});

test('unapproved users cannot update and administrative fields cannot be changed', async () => {
  const f = setup({members: [['resident-a', profile({approvalStatus: 'pendiente'})]]});
  await assert.rejects(f.identity.updateOwnProfile('resident-a', changed()), {code: 'permission-denied'});
  const approved = setup();
  await approved.identity.updateOwnProfile('resident-a', changed({role: 'admin', approvalStatus: 'rechazado', userId: 'someone-else'}));
  assert.equal(approved.data.users.get('resident-a').role, 'vecino');
  assert.equal(approved.data.users.get('resident-a').approvalStatus, 'aprobado');
});

test('withdrawal freezes further profile corrections but permits an administrator retry', async () => {
  const f = setup();
  await f.identity.beginWithdrawal('resident-a');
  await assert.rejects(f.identity.updateOwnProfile('resident-a', changed()), {code: 'permission-denied'});
  const retry = await f.identity.beginWithdrawal('resident-a');
  assert.equal(retry.exists, true);
  assert.equal(f.data.users.get('resident-a').dni, '00000001');
});

test('Auth failure leaves Firestore unchanged and a failed commit restores Auth', async () => {
  const f = setup({authError: 'auth/email-already-exists'});
  await assert.rejects(f.identity.updateOwnProfile('resident-a', changed()), {code: 'already-exists'});
  assert.equal(f.data.users.get('resident-a').dni, '00000001');
  assert.equal(f.data.accessRequests.get('request-a').lookupDni, undefined);
  const failed = setup({failWrite: true});
  await assert.rejects(failed.identity.updateOwnProfile('resident-a', changed()), /Simulated Firestore failure/);
  assert.equal(failed.data.users.get('resident-a').dni, '00000001');
  assert.equal(failed.authWrites.length, 2);
  assert.equal(failed.authWrites[1].email, 'resident@example.com');
});

test('concurrent profiles cannot claim the same DNI', async () => {
  const f = setup({members: [['resident-a', profile()], ['resident-b', profile({dni: '00000004'})]]});
  const results = await Promise.allSettled([
    f.identity.updateOwnProfile('resident-a', changed()),
    f.identity.updateOwnProfile('resident-b', changed()),
  ]);
  assert.equal(results.filter((result) => result.status === 'fulfilled').length, 1);
  assert.equal([...f.data.users.values()].filter((value) => value.dni === '00000002').length, 1);
});

test('approval reserves the DNI, preserves submitted fields and blocks competing identities', async () => {
  const f = setup({members: [], requests: [['request-a', application({status: 'pendiente', approvedUserId: null})]]});
  await f.identity.saveApprovedProfile(f.db.collection('accessRequests').doc('request-a'),
    'resident-a', profile(), {status: 'aprobado'});
  assert.equal(f.data.memberDniKeys.get(key('00000001')).userId, 'resident-a');
  assert.equal(f.data.accessRequests.get('request-a').name, 'Original Resident');
  assert.equal((await f.identity.findRequestStatus('00000001')).request.email, 're*****t@example.com');
  await assert.rejects(f.identity.saveApprovedProfile(f.db.collection('accessRequests').doc('request-a'),
    'resident-b', profile(), {status: 'aprobado'}), {code: 'failed-precondition'});
});

test('approval transaction refuses any final request state without creating a profile or keys', async () => {
  for (const status of ['rechazado', 'aprobado', 'retirado']) {
    const f = setup({members: [], requests: [['request-a', application({status, approvedUserId: null})]]});
    const before = JSON.stringify([...f.data.accessRequests]);
    await assert.rejects(f.identity.saveApprovedProfile(f.db.collection('accessRequests').doc('request-a'),
      'new-resident', profile(), {status: 'aprobado'}), {code: 'failed-precondition'});
    assert.equal(JSON.stringify([...f.data.accessRequests]), before);
    assert.equal(f.data.users.size, 0);
    assert.equal(f.data.memberDniKeys.size, 0);
    assert.equal(f.data.memberEmailKeys.size, 0);
    assert.equal(f.authWrites.length, 0);
  }
});
