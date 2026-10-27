// Header validation is format identification, not an antivirus or full decoder.
const test = require('node:test');
const assert = require('node:assert/strict');
const {validStoredFileHeader} = require('../content_attachments');
const {revokeLegacyDownloadTokens} = require('../download_token_cleanup');
const headers = {
  'image/jpeg': Buffer.from([255, 216, 255]),
  'image/png': Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
  'image/webp': Buffer.from('RIFF0000WEBP'),
  'application/pdf': Buffer.from('%PDF-1.4'),
};
for (const [type, bytes] of Object.entries(headers)) {
  test(`real header identifies ${type}; caller-declared MIME alone does not`, () => {
    assert.equal(validStoredFileHeader(bytes, type), true);
    assert.equal(validStoredFileHeader(Buffer.from('<html>fake</html>'), type), false);
    assert.equal(validStoredFileHeader(Buffer.alloc(0), type), false);
    for (const other of Object.keys(headers).filter(t => t !== type)) assert.equal(validStoredFileHeader(bytes, other), false);
  });
}
test('unsupported signatures and non-byte inputs fail closed', () => {
  for (const type of ['image/heic', 'image/heif', 'image/svg+xml', 'text/html', null]) {
    assert.equal(validStoredFileHeader(headers['image/png'], type), false);
  }
  assert.equal(validStoredFileHeader('not bytes', 'image/png'), false);
});

test('legacy token cleanup is read-only by default and never deletes files or unrelated metadata', async () => {
  const records = new Map([
    ['projects/p/photos/legacy.png', {uploadedBy: 'fictional-owner', firebaseStorageDownloadTokens: 'fictional-token'}],
    ['events/e/minutes/legacy.pdf', {uploadedBy: 'fictional-owner', firebaseStorageDownloadTokens: 'fictional-token'}],
    ['reports/r/photos/new.png', {uploadedBy: 'fictional-owner'}],
    ['events/e/unknown/untouched.bin', {firebaseStorageDownloadTokens: 'fictional-token'}],
  ]);
  const writes = [];
  const bucket = {getFiles: async ({prefix}) => [[...records].filter(([name]) => name.startsWith(prefix)).map(([name]) => ({name,
    getMetadata: async () => [{metadata: records.get(name), metageneration: '1'}],
    setMetadata: async (data, options) => {writes.push({name, data, options}); records.set(name, data.metadata);},
    delete: () => assert.fail('Cleanup must never delete files'),
  }))]};
  assert.deepEqual(await revokeLegacyDownloadTokens({bucket}), {candidates: 2, revocationRequests: 0, dryRun: true});
  assert.equal(writes.length, 0);
  assert.deepEqual(await revokeLegacyDownloadTokens({bucket, apply: true}), {candidates: 2, revocationRequests: 2, dryRun: false});
  assert.equal(writes.length, 2);
  assert.ok(writes.every(w => w.data.metadata.uploadedBy === 'fictional-owner' && w.data.metadata.firebaseStorageDownloadTokens === null));
  assert.equal(records.get('events/e/unknown/untouched.bin').firebaseStorageDownloadTokens, 'fictional-token');
});
