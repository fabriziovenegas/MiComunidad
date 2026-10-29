const test = require('node:test');
const assert = require('node:assert/strict');
const {validStoredFileFormat, storedFileTypeForName} = require('../content_attachments');
const {createAccessRequestSubmission, activeAccountConflictMessage} = require('../access_request_submission');
const {fixture, HttpsError} = require('./helpers/identity_fixture.cjs');

const formats = {
  jpg: ['image/jpeg', Buffer.from([255, 216, 255])],
  jpeg: ['image/jpeg', Buffer.from([255, 216, 255])],
  png: ['image/png', Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])],
  webp: ['image/webp', Buffer.from('RIFF0000WEBP')],
  pdf: ['application/pdf', Buffer.from('%PDF-1.7')],
};
for (const [extension, [mime]] of Object.entries(formats)) {
  for (const [actual, [actualMime, header]] of Object.entries(formats)) {
    test(`actual ${actual} must match .${extension}, its MIME and header`, () => {
      assert.equal(validStoredFileFormat(header, actualMime, `file.${extension.toUpperCase()}`), mime === actualMime);
      if (mime !== actualMime) assert.equal(validStoredFileFormat(header, mime, `file.${extension}`), false);
    });
  }
}
test('HEIC/HEIF and unsupported stored formats remain disabled', () => {
  for (const extension of ['heic', 'heif', 'gif', 'svg', 'exe']) {
    assert.equal(storedFileTypeForName(`photo.${extension}`), undefined);
  }
});

const application = (patch = {}) => ({requestId: 'fictional-request', name: 'Fictional Applicant',
  dni: '00000001', phone: '000000001', email: 'applicant@example.com', address: 'Fictional address',
  timeLivingHere: '1 a 5 años', reason: 'Fictional test',
  identityDocumentPath: 'access_requests/anonymous/identity/document.pdf', ...patch});
const member = (patch = {}) => ({nombre: 'Fictional Member', dni: '00000001', email: 'member@example.com',
  role: 'vecino', approvalStatus: 'aprobado', ...patch});
function endpoint(f, {mime = 'application/pdf', header = formats.pdf[1]} = {}) {
  return createAccessRequestSubmission({identity: f.identity, HttpsError,
    storage: () => ({bucket: () => ({name: 'demo-bucket', file: () => ({bucket: {name: 'demo-bucket'},
      getMetadata: async () => [{size: '100', contentType: mime, metadata: {uploadedBy: 'anonymous'}}],
      download: async () => [header], setMetadata: async () => {},
    })})})});
}
const request = (patch = {}) => ({auth: {uid: 'anonymous', token: {firebase: {sign_in_provider: 'anonymous'}}}, data: application(patch)});

for (const kind of ['dni', 'email', 'authentication']) {
  test(`active ${kind} conflict is generic at the public callable boundary`, async () => {
    const f = fixture({members: kind === 'authentication' ? [] : [['member', member(kind === 'email' ?
      {dni: '00000009', email: 'applicant@example.com'} : {})]]});
    if (kind === 'authentication') f.auth.getUserByEmail = async () => ({uid: 'external-account'});
    await assert.rejects(endpoint(f)(request()), error => {
      assert.equal(error.code, 'already-exists');
      assert.equal(error.message, activeAccountConflictMessage);
      assert.deepEqual(error.details, {reason: 'active-account-conflict'});
      assert.equal(/DNI|correo/.test(error.message), false);
      return true;
    });
    assert.equal(f.data.accessRequests.size, 0);
  });
}
test('pending duplicate and invalid DNI are not remapped to an active account', async () => {
  const pending = fixture({requests: [['pending', {...application(), status: 'pendiente'}]]});
  await assert.rejects(endpoint(pending)(request()), error => error.code === 'already-exists' &&
    error.message.includes('solicitud pendiente') && error.message !== activeAccountConflictMessage);
  const invalid = fixture();
  await assert.rejects(endpoint(invalid)(request({dni: 'bad'})), error =>
    error.code === 'invalid-argument' && error.message !== activeAccountConflictMessage);
});
test('a renamed identity PDF is rejected and a JPG photograph remains accepted', async () => {
  const f = fixture();
  await assert.rejects(endpoint(f)(request({identityDocumentPath: 'access_requests/anonymous/identity/document.jpg'})),
    error => error.code === 'invalid-argument' && error.message.includes('extensión'));
  assert.equal(f.data.accessRequests.size, 0);
  const photo = fixture();
  assert.deepEqual(await endpoint(photo, {mime: 'image/jpeg', header: formats.jpg[1]})(
    request({identityDocumentPath: 'access_requests/anonymous/identity/document.jpeg'})),
  {requestId: 'fictional-request'});
});
