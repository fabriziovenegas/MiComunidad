// Fictional data only. No Firebase connection or email delivery.
const test = require('node:test');
const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const {fixture, HttpsError} = require('./helpers/identity_fixture.cjs');
const {createAccessRequestSubmission} = require('../access_request_submission');

const key = (dni) => createHash('sha256').update(dni).digest('hex');
const date = (n) => ({toMillis: () => n, toDate: () => new Date(n)});
const submission = (extra = {}) => ({requestId: 'request-a', name: 'Fictional Applicant',
  dni: '00000001', phone: '000000001', email: 'applicant@example.com',
  address: 'Fictional address', timeLivingHere: '1 a 5 años', reason: 'Fictional application',
  identityDocumentPath: 'access_requests/anonymous-a/identity/document.pdf',
  identityDocumentUrl: 'https://example.com/fictional-document', ...extra});
const member = (extra = {}) => ({nombre: 'Current Resident', dni: '00000001',
  email: 'current@example.com', phone: '000000001', address: 'Current fictional address',
  timeLivingHere: '1 a 5 años', reason: 'Fictional reason', role: 'vecino',
  approvalStatus: 'aprobado', ...extra});

for (const sameEmail of [false, true]) {
  test(`two simultaneous submissions reserve one DNI (same email: ${sameEmail})`, async () => {
    const f = fixture();
    const results = await Promise.allSettled([
      f.identity.submitAccessRequest('anonymous-a', submission()),
      f.identity.submitAccessRequest('anonymous-b', submission({requestId: 'request-b',
        email: sameEmail ? 'applicant@example.com' : 'other@example.com'})),
    ]);
    assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
    assert.equal(results.find((r) => r.status === 'rejected').reason.code, 'already-exists');
    assert.equal(f.data.accessRequests.size, 1);
    assert.equal(f.data.memberDniKeys.size, 1);
    assert.equal(f.data.users.size, 0);
    assert.equal(f.authWrites.length, 0);
  });
}

test('a sequential duplicate and an old pending request without a reservation are blocked', async () => {
  for (const legacy of [false, true]) {
    const f = fixture({requests: legacy ? [['legacy', {...submission(), status: 'pendiente'}]] : []});
    if (!legacy) await f.identity.submitAccessRequest('anonymous-a', submission());
    await assert.rejects(f.identity.submitAccessRequest('anonymous-b', submission({requestId: 'request-b'})),
      {code: 'already-exists'});
    assert.equal(f.data.accessRequests.size, 1);
  }
});

test('network retry is idempotent, but an identifier cannot overwrite another application', async () => {
  const f = fixture();
  await f.identity.submitAccessRequest('anonymous-a', submission());
  const original = {...f.data.accessRequests.get('request-a')};
  assert.deepEqual(await f.identity.submitAccessRequest('anonymous-a', submission()), {requestId: 'request-a'});
  await assert.rejects(f.identity.submitAccessRequest('anonymous-b', submission()), {code: 'already-exists'});
  await assert.rejects(f.identity.submitAccessRequest('anonymous-a', submission({name: 'Changed Applicant'})),
    {code: 'already-exists'});
  assert.deepEqual(f.data.accessRequests.get('request-a'), original);
});

test('rejection, withdrawal and deletion permit a new application without overwriting history', async () => {
  for (const status of ['rechazado', 'retirado', 'deleted']) {
    const f = fixture();
    await f.identity.submitAccessRequest('anonymous-a', submission());
    if (status === 'deleted') f.data.accessRequests.delete('request-a');
    else f.data.accessRequests.set('request-a', {...f.data.accessRequests.get('request-a'), status});
    const original = f.data.accessRequests.get('request-a');
    await f.identity.submitAccessRequest('anonymous-b', submission({requestId: 'request-b'}));
    assert.equal(f.data.accessRequests.get('request-b').status, 'pendiente');
    assert.equal(f.data.accessRequests.get('request-a'), original);
    assert.equal(f.data.memberDniKeys.get(key('00000001')).requestId, 'request-b');
  }
});

test('an approved member blocks registration even without an application or DNI reservation', async () => {
  const f = fixture({members: [['resident-a', member()]]});
  await assert.rejects(f.identity.submitAccessRequest('anonymous-a', submission()), {code: 'already-exists'});
  assert.equal(f.data.accessRequests.size, 0);
});

test('the pending reservation supports approval and later DNI corrections', async () => {
  const f = fixture();
  await f.identity.submitAccessRequest('anonymous-a', submission());
  const original = {...f.data.accessRequests.get('request-a')};
  await f.identity.saveApprovedProfile(f.db.collection('accessRequests').doc('request-a'),
    'resident-a', member(), {status: 'aprobado'});
  assert.equal(f.data.memberDniKeys.get(key('00000001')).userId, 'resident-a');
  assert.equal(f.data.memberDniKeys.get(key('00000001')).requestId, undefined);
  await f.identity.updateOwnProfile('resident-a', member({dni: '00000002'}));
  assert.equal((await f.identity.findRequestStatus('00000001')).request, null);
  assert.equal((await f.identity.findRequestStatus('00000002')).request.status, 'aprobado');
  await f.identity.submitAccessRequest('anonymous-b', submission({requestId: 'request-b'}));
  assert.equal((await f.identity.findRequestStatus('00000001')).request.status, 'pendiente');
  for (const field of ['name', 'dni', 'phone', 'email', 'address', 'timeLivingHere', 'reason']) {
    assert.equal(f.data.accessRequests.get('request-a')[field], original[field]);
  }
});

test('pending submissions and profile corrections share the same DNI conflict checks', async () => {
  const f = fixture({members: [['resident-a', member({dni: '00000002'})]]});
  const results = await Promise.allSettled([
    f.identity.submitAccessRequest('anonymous-a', submission()),
    f.identity.updateOwnProfile('resident-a', member()),
  ]);
  assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
  assert.equal(results.find((r) => r.status === 'rejected').reason.code, 'already-exists');
});

test('invalid data and commit failures leave both the application and reservation unchanged', async () => {
  for (const patch of [{dni: 'invalid'}, {phone: 'short'}, {email: 'invalid'}, {name: ''},
    {requestId: '../invalid'}, {address: ''}, {reason: 'x'.repeat(1001)}, {timeLivingHere: 'invented'}]) {
    const f = fixture();
    await assert.rejects(f.identity.submitAccessRequest('anonymous-a', submission(patch)), {code: 'invalid-argument'});
    assert.equal(f.data.accessRequests.size, 0);
    assert.equal(f.data.memberDniKeys.size, 0);
  }
  const f = fixture({failWrite: true});
  await assert.rejects(f.identity.submitAccessRequest('anonymous-a', submission()), /Simulated Firestore failure/);
  assert.equal(f.data.accessRequests.size, 0);
  assert.equal(f.data.memberDniKeys.size, 0);
});

test('caller-supplied approval, ownership and timestamps never become authoritative', async () => {
  const f = fixture();
  await f.identity.submitAccessRequest('anonymous-a', submission({status: 'aprobado',
    approvedUserId: 'someone-else', applicantUid: 'someone-else', role: 'admin', createdAt: 'caller-time'}));
  const stored = f.data.accessRequests.get('request-a');
  assert.equal(stored.applicantUid, 'anonymous-a');
  assert.equal(stored.status, 'pendiente');
  assert.equal(stored.createdAt, 'server-time');
  assert.equal(stored.approvedUserId, undefined);
  assert.equal(stored.role, undefined);
});

test('registration preserves short names, punctuation, accents and the original submitted text', async () => {
  for (const name of ['Li', "Ana O'Connor", 'María José']) {
    const f = fixture();
    await f.identity.submitAccessRequest('anonymous-a', submission({name}));
    assert.equal(f.data.accessRequests.get('request-a').name, name);
  }
});

test('a linked approved account wins over newer rejected or pending duplicate requests', async () => {
  for (const status of ['rechazado', 'pendiente']) {
    const f = fixture({members: [['resident-a', member()]], requests: [
      ['approved', {...submission(), status: 'aprobado', approvedUserId: 'resident-a', createdAt: date(1000)}],
      ['duplicate', {...submission({name: 'Other Applicant'}), status, createdAt: date(2000)}],
    ]});
    const visible = (await f.identity.findRequestStatus('00000001')).request;
    assert.equal(visible.status, 'aprobado');
    assert.equal(Object.hasOwn(visible, 'name'), false);
    assert.equal(visible.email, 'cu****t@example.com');
    assert.deepEqual(Object.keys(visible).sort(), ['createdAt', 'email', 'status']);
  }
});

test('without a live approved account, the latest application and withdrawal stay visible', async () => {
  const f = fixture({requests: [
    ['older', {...submission(), status: 'aprobado', approvedUserId: 'deleted-user', createdAt: date(1000)}],
    ['newer', {...submission(), status: 'rechazado', createdAt: date(2000)}],
  ]});
  assert.equal((await f.identity.findRequestStatus('00000001')).request.status, 'rechazado');
  f.data.accessRequests.delete('newer');
  assert.equal((await f.identity.findRequestStatus('00000001')).request.status, 'retirado');
});

function endpoint(options = {}) {
  const calls = [];
  const metadata = {size: '1234', contentType: 'application/pdf', metadata: {uploadedBy: 'anonymous-a'},
    ...options.metadata};
  const handler = createAccessRequestSubmission({HttpsError,
    identity: {submitAccessRequest: async (uid, data) => {calls.push({uid, data}); return {requestId: data.requestId};}},
    storage: () => ({bucket: () => ({file: (name) => ({name, bucket: {name: 'demo-documents.appspot.com'}, setMetadata: async () => {}, getMetadata: async () => {
      if (options.storageError) throw Error('Simulated storage failure'); return [metadata];
    }, download: async () => [options.header ||
      (metadata.contentType === 'image/jpeg' ? Buffer.from([255, 216, 255]) :
        metadata.contentType === 'image/png' ? Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]) :
          metadata.contentType === 'image/webp' ? Buffer.from('RIFF0000WEBP') : Buffer.from('%PDF-1.4'))]})})}),
    getDownloadURL: async () => 'https://example.com/verified-document',
  });
  return {handler, calls};
}
const caller = (data = (() => {const value = submission(); delete value.identityDocumentUrl; return value;})()) => ({auth: {uid: 'anonymous-a',
  token: {firebase: {sign_in_provider: 'anonymous'}}}, data});

test('the callable requires anonymous authentication and validates attachment ownership', async () => {
  const f = endpoint();
  await assert.rejects(f.handler({data: submission()}), {code: 'unauthenticated'});
  await assert.rejects(f.handler({...caller(), auth: {uid: 'anonymous-a',
    token: {firebase: {sign_in_provider: 'password'}}}}), {code: 'permission-denied'});
  for (const identityDocumentPath of ['access_requests/another-user/identity/a.pdf',
    'access_requests/anonymous-a/identity/../a.pdf', '', 'access_requests/anonymous-a/identity/']) {
    await assert.rejects(f.handler(caller(submission({identityDocumentPath}))), {code: 'invalid-argument'});
  }
  assert.equal(f.calls.length, 0);
});

test('missing, oversized, unsupported or foreign attachments never create an application', async () => {
  for (const metadata of [{size: '0'}, {size: String(5 * 1024 * 1024 + 1)},
    {size: 'not-a-number'}, {contentType: 'text/plain'}, {metadata: {uploadedBy: 'another-user'}}]) {
    const f = endpoint({metadata});
    await assert.rejects(f.handler(caller()), {code: 'invalid-argument'});
    assert.equal(f.calls.length, 0);
  }
  const f = endpoint({storageError: true});
  await assert.rejects(f.handler(caller()), {code: 'failed-precondition'});
  assert.equal(f.calls.length, 0);
});

test('download URLs come from the verified server-side attachment, not from the caller', async () => {
  const f = endpoint();
  await assert.rejects(f.handler(caller(submission({identityDocumentUrl: 'https://example.com/untrusted'}))), {code: 'invalid-argument'});
  assert.deepEqual(await f.handler(caller()), {requestId: 'request-a'});
  assert.equal(f.calls[0].data.identityDocumentUrl, 'gs://demo-documents.appspot.com/access_requests/anonymous-a/identity/document.pdf');
});

for (const contentType of ['image/jpeg', 'image/png', 'image/webp', 'application/pdf']) {
  test(`identity attachment accepts ${contentType} with the same ownership and size checks`, async () => {
    const f = endpoint({metadata: {contentType}});
    const data = submission({identityDocumentPath: 'access_requests/anonymous-a/identity/document.webp'});
    delete data.identityDocumentUrl;
    await f.handler(caller(data));
    assert.equal(f.calls.length, 1);
    assert.equal(f.calls[0].uid, 'anonymous-a');
  });
}
for (const contentType of ['image/heic', 'image/heif', 'image/gif', 'image/svg+xml']) {
  test(`unconfirmed or unsupported identity MIME ${contentType} remains blocked`, async () => {
    const f = endpoint({metadata: {contentType}});
    await assert.rejects(f.handler(caller()), {code: 'invalid-argument'});
    assert.equal(f.calls.length, 0);
  });
}
