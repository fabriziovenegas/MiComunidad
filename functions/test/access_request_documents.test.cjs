// Fictional in-memory data only. Never connects to Firebase.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const {fixture, HttpsError} = require('./helpers/identity_fixture.cjs');
const {createAccessRequestSubmission} = require('../access_request_submission');

const fields = {requestId: 'request-documents', name: 'Fictional Applicant', dni: '00000001',
  phone: '000000001', email: 'applicant@example.com', address: 'Fictional address',
  timeLivingHere: '1 a 5 años', reason: 'Fictional application'};
const root = 'access_requests/anonymous/identity/';
const paths = [root + '1_receipt.pdf', root + '2_photo.jpg', root + '3_photo.webp'];
const formats = {
  pdf: ['application/pdf', Buffer.from('%PDF-1.7')],
  jpg: ['image/jpeg', Buffer.from([255, 216, 255])],
  webp: ['image/webp', Buffer.from('RIFF0000WEBP')],
};
function setup() {
  const f = fixture();
  const files = new Map(paths.map(p => [p, {size: '1024', contentType: formats[p.split('.').at(-1)][0],
    metadata: {uploadedBy: 'anonymous', firebaseStorageDownloadTokens: 'fictional-token'}}]));
  const calls = [];
  const handler = createAccessRequestSubmission({identity: f.identity, HttpsError,
    storage: () => ({bucket: () => ({file: name => ({bucket: {name: 'demo-documents'},
      getMetadata: async () => {calls.push(name); if (!files.has(name)) throw Error('Missing'); return [files.get(name)];},
      download: async () => [files.get(name).header || formats[name.split('.').at(-1)][1]],
      setMetadata: async value => {files.set(name, {...files.get(name), ...value});},
    })})})});
  const call = (data, auth = {uid: 'anonymous', token: {firebase: {sign_in_provider: 'anonymous'}}}) => handler({auth, data});
  return {...f, files, calls, call};
}

for (const count of [1, 2, 3]) test(`${count} validated files belong to one pending request and remain private`, async () => {
  const f = setup();
  const data = {...fields, identityDocumentPaths: paths.slice(0, count)};
  assert.deepEqual(await f.call(data), {requestId: fields.requestId});
  assert.equal(f.data.accessRequests.size, 1);
  const saved = f.data.accessRequests.get(fields.requestId);
  assert.equal(saved.identityDocuments.length, count);
  assert.deepEqual(saved.identityDocuments.map(d => d.storagePath), paths.slice(0, count));
  assert.equal(saved.identityDocumentUrl, saved.identityDocuments[0].url);
  assert.equal(saved.identityDocumentPath, paths[0]);
  assert.equal(saved.status, 'pendiente');
  for (const document of saved.identityDocuments) {
    assert.equal(document.url, `gs://demo-documents/${document.storagePath}`);
    assert.equal(document.size, 1024);
    assert.equal(f.files.get(document.storagePath).metadata.firebaseStorageDownloadTokens, null);
  }
  assert.deepEqual(await f.call(data), {requestId: fields.requestId});
  assert.equal(f.data.accessRequests.size, 1, 'retry does not duplicate a request');
  const publicResult = (await f.identity.findRequestStatus(fields.dni)).request;
  assert.deepEqual(Object.keys(publicResult).sort(), ['createdAt', 'email', 'status']);
});

test('old single-document calls and their historical retry fingerprint still work', async () => {
  const f = setup();
  const data = {...fields, identityDocumentPath: paths[0]};
  const old = {applicantUid: 'anonymous', ...fields, identityDocumentPath: paths[0],
    identityDocumentUrl: `gs://demo-documents/${paths[0]}`, status: 'pendiente'};
  const profileFields = ['nombre', 'dni', 'phone', 'email', 'address', 'timeLivingHere', 'reason'];
  old.submissionFingerprint = createHash('sha256').update(JSON.stringify([
    'anonymous', ...profileFields.map(k => k === 'nombre' ? fields.name : fields[k]), paths[0],
  ])).digest('hex');
  f.data.accessRequests.set(fields.requestId, old);
  assert.deepEqual(await f.call(data), {requestId: fields.requestId});
  assert.deepEqual(f.data.accessRequests.get(fields.requestId), old, 'no migration or historical overwrite');
  assert.equal(f.data.memberDniKeys.size, 0);
});

test('an empty list, a fourth file, duplicate paths and forged fields are rejected before Storage', async () => {
  for (const list of [[], [...paths, root + 'fourth.pdf'], [paths[0], paths[0]], ['../foreign.pdf'],
    [paths[0], 'access_requests/other/identity/document.pdf'], [paths[0], null]]) {
    const f = setup();
    await assert.rejects(f.call({...fields, identityDocumentPaths: list}), {code: 'invalid-argument'});
    assert.equal(f.calls.length, 0);
    assert.equal(f.data.accessRequests.size, 0);
  }
  for (const patch of [{identityDocumentUrl: 'https://example.com/forged'}, {role: 'admin'},
    {identityDocumentPath: paths[0]}, {identityDocuments: [{url: 'https://example.com/forged'}]}]) {
    const f = setup();
    await assert.rejects(f.call({...fields, identityDocumentPaths: paths, ...patch}), {code: 'invalid-argument'});
    assert.equal(f.data.accessRequests.size, 0);
  }
});

for (const failure of ['size', 'format', 'mime', 'owner', 'missing']) {
  test(`the second file fails ${failure}: no partial request or DNI/email reservation`, async () => {
    const f = setup();
    if (failure === 'missing') f.files.delete(paths[1]);
    else {
      const metadata = f.files.get(paths[1]);
      if (failure === 'size') metadata.size = String(5 * 1024 * 1024 + 1);
      if (failure === 'format') metadata.header = formats.pdf[1];
      if (failure === 'mime') metadata.contentType = 'application/pdf';
      if (failure === 'owner') metadata.metadata.uploadedBy = 'other';
    }
    await assert.rejects(f.call({...fields, identityDocumentPaths: paths}),
      {code: failure === 'missing' ? 'failed-precondition' : 'invalid-argument'});
    assert.equal(f.data.accessRequests.size, 0);
    assert.equal(f.data.memberDniKeys.size, 0);
    assert.equal(f.data.memberEmailKeys.size, 0);
  });
}

test('all files keep the exact 5 MB inclusive limit', async () => {
  const f = setup();
  for (const p of paths) f.files.get(p).size = String(5 * 1024 * 1024);
  await f.call({...fields, identityDocumentPaths: paths});
  assert.ok(f.data.accessRequests.get(fields.requestId).identityDocuments.every(d => d.size === 5 * 1024 * 1024));
});

test('a retry cannot replace a second or third file in an existing request', async () => {
  const f = setup();
  await f.call({...fields, identityDocumentPaths: paths});
  const before = structuredClone(f.data.accessRequests.get(fields.requestId));
  await assert.rejects(f.call({...fields, identityDocumentPaths: [paths[0], paths[2]]}), {code: 'already-exists'});
  assert.deepEqual(f.data.accessRequests.get(fields.requestId), before);
});

test('anonymous ownership remains required; normal, pending and unauthenticated callers cannot submit', async () => {
  const f = setup();
  await assert.rejects(f.call({...fields, identityDocumentPaths: paths}, null), {code: 'unauthenticated'});
  for (const provider of ['password', 'custom', 'google.com']) {
    await assert.rejects(f.call({...fields, identityDocumentPaths: paths},
      {uid: 'anonymous', token: {firebase: {sign_in_provider: provider}}}), {code: 'permission-denied'});
  }
  assert.equal(f.data.accessRequests.size, 0);
});
