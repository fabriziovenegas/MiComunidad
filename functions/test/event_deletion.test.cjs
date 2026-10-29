// In-memory fictional data only. Never connects to Firebase.
const test = require('node:test');
const assert = require('node:assert/strict');
const {createEventDeletion} = require('../event_deletion');
const {HttpsError} = require('./helpers/identity_fixture.cjs');

function fixture() {
  const rows = new Map([
    ['users/admin', {role: 'admin', approvalStatus: 'aprobado'}],
    ['users/neighbor', {role: 'vecino', approvalStatus: 'aprobado'}],
    ['users/pending', {role: 'admin', approvalStatus: 'pendiente'}],
    ['events/activity', {title: 'Fictional activity'}],
    ['events/other', {title: 'Unrelated activity'}],
  ]);
  const objects = new Map();
  const operations = [];
  const options = {failFile: null, failRecords: false, duringParentDeletion: null};
  const snapshot = path => ({ref: reference(path), id: path.split('/').at(-1), exists: rows.has(path), data: () => rows.get(path)});
  function reference(path) {
    return {path, get: async () => snapshot(path),
      listCollections: async () => [...new Set([...rows.keys()].filter(p => p.startsWith(path + '/') &&
        p.slice(path.length + 1).includes('/')).map(p => p.slice(0, path.length + 1) + p.slice(path.length + 1).split('/')[0]))].map(p => collection(p))};
  }
  function collection(path, cursor = '', limit = 400) {
    return {path, doc: id => reference(`${path}/${id}`),
      orderBy: () => collection(path, cursor, limit), startAfter: last => collection(path, last.ref.path, limit),
      limit: n => collection(path, cursor, n), get: async () => ({docs: [...rows.keys()].filter(p => p.startsWith(path + '/') &&
        !p.slice(path.length + 1).includes('/') && p > cursor).sort().slice(0, limit).map(snapshot)})};
  }
  const db = {collection,
    runTransaction: async callback => {
      const deletes = [];
      await callback({get: ref => ref.get(), delete: ref => deletes.push(ref.path)});
      for (const path of deletes) {rows.delete(path); operations.push(['parent', path]);}
      await options.duringParentDeletion?.();
    },
    recursiveDelete: async ref => {
      if (options.failRecords) throw Error('Fictional Firestore failure');
      for (const path of [...rows.keys()]) if (path.startsWith(ref.path + '/')) rows.delete(path);
      operations.push(['records', ref.path]);
    }};
  const bucket = {name: 'demo-bucket', getFiles: async query => {
    assert.equal(query.prefix, 'events/activity/');
    const names = [...objects.keys()].filter(n => n.startsWith(query.prefix) && n > (query.pageToken || '')).sort();
    const page = names.slice(0, query.maxResults);
    return [page.map(name => ({name, metadata: {generation: objects.get(name)}})),
      names.length > page.length ? {pageToken: page.at(-1)} : null];
  }, file: (name, {generation}) => ({delete: async () => {
    assert.ok(name.startsWith('events/activity/'));
    if (options.failFile === name) throw Error('Fictional Storage failure');
    if (!objects.has(name)) throw Object.assign(Error('Missing file'), {code: 404});
    assert.equal(objects.get(name), generation);
    objects.delete(name); operations.push(['file', name]);
  }})};
  const remove = createEventDeletion({firestore: db, storage: () => ({bucket: () => bucket}), HttpsError});
  const call = (uid = 'admin', data = {eventId: 'activity'}) => remove({auth: uid ? {uid} : null, data});
  function attach(kind, id, {url, path} = {}) {
    path ||= `events/activity/${kind}/${id}.jpg`;
    objects.set(path, '1');
    rows.set(`events/activity/${kind}/${id}`, {storagePath: path, url: url || `gs://demo-bucket/${path}`});
  }
  return {rows, objects, operations, options, call, attach};
}

test('definitive deletion removes photos, minutes, other files and nested records only for this activity', async () => {
  const f = fixture();
  f.attach('photos', 'photo'); f.attach('minutes', 'acta', {path: 'events/activity/minutes/acta.pdf'});
  f.objects.set('events/activity/documents/unreferenced.pdf', '1');
  f.objects.set('events/other/photos/keep.jpg', '1');
  f.objects.set('events/activity-similar/photos/keep.jpg', '1');
  f.objects.set('reports/activity/photos/keep.jpg', '1');
  f.rows.set('events/activity/comments/comment', {text: 'Fictional comment'});
  f.rows.set('events/activity/photos/photo/nested/record', {name: 'Nested metadata'});
  assert.deepEqual(await f.call(), {success: true});
  assert.equal([...f.rows.keys()].some(p => p === 'events/activity' || p.startsWith('events/activity/')), false);
  assert.deepEqual([...f.objects.keys()].sort(), ['events/activity-similar/photos/keep.jpg', 'events/other/photos/keep.jpg', 'reports/activity/photos/keep.jpg']);
  assert.equal(f.rows.has('events/other'), true);
  assert.equal(f.operations[0][0], 'parent');
});
test('anonymous, pending and neighbor accounts cannot delete an activity', async () => {
  for (const uid of [null, 'pending', 'neighbor', 'missing']) {
    const f = fixture(); f.attach('photos', 'photo');
    await assert.rejects(f.call(uid), error => ['unauthenticated', 'permission-denied'].includes(error.code));
    assert.equal(f.rows.has('events/activity'), true); assert.equal(f.objects.size, 1);
  }
});
test('invalid identifiers and caller-supplied paths never reach deletion', async () => {
  for (const data of [{eventId: '../other'}, {eventId: 'activity/other'}, {eventId: 'activity', prefix: 'reports/'}, {}, null]) {
    const f = fixture();
    await assert.rejects(f.call('admin', data), {code: 'invalid-argument'});
    assert.equal(f.operations.length, 0);
  }
});
test('foreign URLs, paths and mismatched references abort before deleting anything', async () => {
  for (const patch of [{storagePath: 'reports/other/photos/a.jpg'}, {url: 'gs://other-bucket/events/activity/photos/a.jpg'},
    {url: 'https://example.com/private.pdf'}, {url: 'gs://demo-bucket/events/activity/photos/different.jpg'}]) {
    const f = fixture(); f.attach('photos', 'photo');
    Object.assign(f.rows.get('events/activity/photos/photo'), patch);
    await assert.rejects(f.call(), {code: 'failed-precondition'});
    assert.equal(f.operations.length, 0); assert.equal(f.objects.size, 1);
  }
});
test('legitimate legacy Firebase URLs remain deletable', async () => {
  const f = fixture(); f.attach('photos', 'photo');
  const row = f.rows.get('events/activity/photos/photo');
  row.url = 'https://firebasestorage.googleapis.com/v0/b/demo-bucket/o/' + encodeURIComponent(row.storagePath) + '?alt=media&token=fictional';
  assert.deepEqual(await f.call(), {success: true});
});
test('all pages and late contributions are cleaned; retries are idempotent', async () => {
  const f = fixture();
  for (let i = 0; i < 451; i++) f.attach('photos', `p${String(i).padStart(4, '0')}`);
  f.options.duringParentDeletion = () => {f.attach('minutes', 'late', {path: 'events/activity/minutes/late.pdf'});};
  assert.deepEqual(await f.call(), {success: true});
  assert.equal(f.objects.size, 0);
  assert.equal([...f.rows.keys()].some(p => p.startsWith('events/activity/')), false);
  f.options.duringParentDeletion = null;
  assert.deepEqual(await f.call(), {success: true});
});
for (const stage of ['files', 'records']) {
  test(`a partial ${stage} failure is reported and a retry finishes an absent parent`, async () => {
    const f = fixture(); f.attach('photos', 'photo');
    if (stage === 'files') f.options.failFile = 'events/activity/photos/photo.jpg';
    else f.options.failRecords = true;
    await assert.rejects(f.call(), error => error.code === 'unavailable' && error.details.reason === 'event-deletion-incomplete');
    assert.equal(f.rows.has('events/activity'), false);
    f.options.failFile = null; f.options.failRecords = false;
    assert.deepEqual(await f.call(), {success: true});
    assert.equal(f.objects.size, 0); assert.equal(f.rows.has('events/activity/photos/photo'), false);
  });
}
