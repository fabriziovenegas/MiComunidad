// Local Firestore emulator only. No SDK credentials or real project are used.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const host = process.env.FIRESTORE_EMULATOR_HOST;
const project = 'demo-micomunidad-report-edit';
const enabled = Boolean(host);
if (enabled && !/^127\.0\.0\.1:\d+$/.test(host)) {
  throw new Error('These tests require a loopback Firestore emulator.');
}
const base = `http://${host}/v1/projects/${project}/databases/(default)/documents`;
function token(uid) {
  const now = Math.floor(Date.now() / 1000);
  const encoded = (v) => Buffer.from(JSON.stringify(v)).toString('base64url');
  return `${encoded({alg: 'none', typ: 'JWT'})}.${encoded({
    iss: `https://securetoken.google.com/${project}`, aud: project,
    sub: uid, user_id: uid, iat: now, exp: now + 3600, auth_time: now,
    firebase: {sign_in_provider: 'password'},
  })}.`;
}
function fields(data) {
  return Object.fromEntries(Object.entries(data).map(([key, value]) => [key,
    typeof value === 'string' ? {stringValue: value} :
      typeof value === 'boolean' ? {booleanValue: value} :
        value === null ? {nullValue: null} : {integerValue: String(value)},
  ]));
}
async function request(route, {method = 'GET', data, uid = 'owner'} = {}) {
  const response = await fetch(route, {
    method,
    headers: {'Content-Type': 'application/json',
      ...(uid ? {Authorization: `Bearer ${uid === 'owner' ? 'owner' : token(uid)}`} : {})},
    body: data ? JSON.stringify(data) : undefined,
  });
  return {status: response.status, body: await response.json()};
}
async function seed(id, report) {
  const result = await request(`${base}/reports/${id}`, {
    method: 'PATCH', data: {fields: fields(report)},
  });
  assert.equal(result.status, 200, JSON.stringify(result.body));
}
async function edit(id, patch, uid = 'neighbor-a', deleted = [], serverTimestamp = true, moderationTimestamp = false) {
  const transforms = [
    ...(serverTimestamp ? [{fieldPath: 'updatedAt', setToServerValue: 'REQUEST_TIME'}] : []),
    ...(moderationTimestamp ? [{fieldPath: 'moderatedAt', setToServerValue: 'REQUEST_TIME'}] : []),
  ];
  const result = await request(`${base}:commit`, {
    method: 'POST', uid, data: {writes: [{
      update: {name: `projects/${project}/databases/(default)/documents/reports/${id}`,
        fields: fields(patch)},
      updateMask: {fieldPaths: Object.keys(patch).concat(deleted)},
      ...(transforms.length ? {updateTransforms: transforms} : {}),
      currentDocument: {exists: true},
    }]},
  });
  return result;
}
const report = (extra = {}) => ({
  createdBy: 'neighbor-a', createdByName: 'Demo Resident',
  title: 'Demo report', description: 'A fictional issue for local testing.',
  location: 'Demo location', category: 'obras', priority: 'media',
  moderationStatus: 'aprobado', status: 'pendiente',
  moderationReason: '', moderatedBy: 'admin-demo', ...extra,
});

test('author-only content editing rules', {skip: !enabled}, async (t) => {
  const source = fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8');
  const rules = await request(`http://${host}/emulator/v1/projects/${project}:securityRules`, {
    method: 'PUT', data: {rules: {files: [{name: 'firestore.rules', content: source}]}},
  });
  assert.equal(rules.status, 200, JSON.stringify(rules.body));
  // Reset only the fixed demo database in the loopback emulator so a repeated
  // run cannot collide with comments left by its previous execution.
  const reset = await request(`http://${host}/emulator/v1/projects/${project}/databases/(default)/documents`, {
    method: 'DELETE',
  });
  assert.equal(reset.status, 200, JSON.stringify(reset.body));
  for (const [uid, role, approvalStatus] of [
    ['neighbor-a', 'vecino', 'aprobado'], ['neighbor-b', 'vecino', 'aprobado'],
    ['admin-demo', 'admin', 'aprobado'], ['unapproved', 'vecino', 'pendiente'],
    ['unapproved-admin', 'admin', 'pendiente'],
  ]) {
    const result = await request(`${base}/users/${uid}`, {
      method: 'PATCH', data: {fields: fields({role, approvalStatus})},
    });
    assert.equal(result.status, 200, JSON.stringify(result.body));
  }
  let serial = 0;
  async function check(name, extra, patch, allowed, uid = 'neighbor-a', deleted = [], serverTimestamp = true, moderationTimestamp = false) {
    await t.test(name, async () => {
      const id = `edit-${++serial}`;
      await seed(id, report(extra));
      const result = await edit(id, patch, uid, deleted, serverTimestamp, moderationTimestamp);
      assert.equal(result.status, allowed ? 200 : 403, JSON.stringify(result.body));
      const stored = await request(`${base}/reports/${id}`);
      assert.equal(stored.body.fields.createdBy.stringValue, extra.createdBy ?? 'neighbor-a');
      if (!allowed) assert.deepEqual(stored.body.fields, fields(report(extra)));
      if (allowed && uid === 'neighbor-a') {
        assert.ok(stored.body.fields.updatedAt.timestampValue);
        assert.equal(stored.body.fields.moderationStatus.stringValue, extra.moderationStatus ?? 'aprobado');
        assert.equal(stored.body.fields.status.stringValue, extra.status ?? 'pendiente');
      }
    });
  }
  for (const moderationStatus of ['pendiente', 'aprobado']) {
    for (const status of ['pendiente', 'en_revision', 'en_proceso']) {
      await check(`owner saves ${moderationStatus}/${status}`, {moderationStatus, status},
          {title: 'Edited demo', description: 'Line one\nLine two', location: '',
            category: 'limpieza', priority: 'alta'}, true);
    }
  }
  await check('another resident cannot edit', {}, {title: 'Blocked'}, false, 'neighbor-b');
  await check('anonymous caller cannot edit', {}, {title: 'Blocked'}, false, null);
  await check('unapproved author cannot edit', {createdBy: 'unapproved'}, {title: 'Blocked'}, false, 'unapproved');
  await check('resolved report is read-only to owner', {status: 'resuelto'}, {title: 'Blocked'}, false);
  await check('rejected moderation is read-only', {moderationStatus: 'rechazado'}, {title: 'Blocked'}, false);
  await check('legacy rejected operational state is read-only', {status: 'rechazado'}, {title: 'Blocked'}, false);
  await check('missing moderation is not silently approved', {moderationStatus: null}, {title: 'Blocked'}, false);
  for (const patch of [
    {createdBy: 'neighbor-b'}, {createdByName: 'Impersonated'}, {status: 'resuelto'},
    {moderationStatus: 'aprobado', status: 'en_proceso'}, {moderationReason: 'Changed'},
    {moderatedBy: 'neighbor-a'}, {createdAt: 'Changed'}, {extraAdminField: true},
  ]) await check('administrative patch denied: ' + Object.keys(patch).join(','),
      {moderationStatus: 'pendiente'}, patch, false);
  for (const patch of [
    {title: ''}, {title: '   '}, {title: 'x'.repeat(161)}, {title: 42},
    {description: '\n\t '}, {description: 'x'.repeat(4001)},
    {location: 'x'.repeat(301)}, {category: 'Obras'}, {priority: 'urgent'},
  ]) await check('invalid content denied: ' + Object.keys(patch).join(','), {}, patch, false);
  await check('title cannot be removed', {}, {}, false, 'neighbor-a', ['title']);
  await check('location cannot be removed', {}, {}, false, 'neighbor-a', ['location']);
  await check('client cannot forge updatedAt', {}, {title: 'Edited', updatedAt: 'fake'},
      false, 'neighbor-a', [], false);
  await check('write needs a server timestamp', {}, {title: 'Edited'},
      false, 'neighbor-a', [], false);
  await check('valid boundary lengths', {}, {title: 'x'.repeat(160),
    description: 'x'.repeat(4000), location: 'x'.repeat(300)}, true);
  await check('existing admin moderation is preserved', {moderationStatus: 'pendiente'},
      {moderationStatus: 'aprobado', moderationReason: null, moderatedBy: 'admin-demo'},
      true, 'admin-demo', [], true, true);
  await check('existing admin rejection is preserved', {moderationStatus: 'pendiente'},
      {moderationStatus: 'rechazado', moderationReason: 'Demo reason', moderatedBy: 'admin-demo'},
      true, 'admin-demo', [], true, true);
  await check('existing admin state updates are preserved', {},
      {status: 'en_proceso'}, true, 'admin-demo');
  for (const moderationStatus of ['pendiente', 'aprobado']) {
    for (const status of ['pendiente', 'en_revision', 'en_proceso']) {
      await check(`admin author edits ${moderationStatus}/${status}`,
          {createdBy: 'admin-demo', moderationStatus, status},
          {title: 'Admin own edit', description: 'Demo description', location: '',
            category: 'limpieza', priority: 'alta'}, true, 'admin-demo');
    }
  }
  for (const patch of [
    {title: 'Other author edit'}, {description: 'Other description'},
    {location: 'Other location'}, {category: 'limpieza'}, {priority: 'alta'},
    {title: 'Other author edit', status: 'en_proceso'}, {createdBy: 'admin-demo'},
    {createdByName: 'Impersonated'}, {extraAdminField: true},
  ]) await check('admin cannot bypass authorship: ' + Object.keys(patch).join(','),
      {}, patch, false, 'admin-demo');
  await check('admin edits own resolved content',
      {createdBy: 'admin-demo', status: 'resuelto'}, {title: 'Own resolved edit'}, true, 'admin-demo');
  await check('admin cannot edit another resolved report',
      {status: 'resuelto'}, {title: 'Blocked'}, false, 'admin-demo');
  await check('unapproved admin cannot edit own resolved report',
      {createdBy: 'unapproved-admin', status: 'resuelto'}, {title: 'Blocked'}, false, 'unapproved-admin');
  for (const patch of [{createdBy: 'neighbor-b'}, {moderationStatus: 'rechazado'},
    {title: ' ', priority: 'invalid'}, {title: 'Edited', status: 'en_proceso'}]) {
    await check('resolved admin content whitelist: ' + Object.keys(patch).join(','),
        {createdBy: 'admin-demo', status: 'resuelto'}, patch, false, 'admin-demo');
  }
  await check('admin cannot edit own rejected content',
      {createdBy: 'admin-demo', moderationStatus: 'rechazado'}, {title: 'Blocked'}, false, 'admin-demo');
  await check('admin cannot mix own content and status in one action',
      {createdBy: 'admin-demo'}, {title: 'Edited', status: 'en_proceso'}, false, 'admin-demo');
  await check('admin cannot mix other content and moderation',
      {moderationStatus: 'pendiente'},
      {title: 'Edited', moderationStatus: 'aprobado', moderationReason: null, moderatedBy: 'admin-demo'},
      false, 'admin-demo', [], true, true);
  for (const createdBy of ['neighbor-a', 'admin-demo']) {
    for (const status of ['pendiente', 'en_proceso', 'resuelto']) {
      await check(`admin updates ${createdBy} status to ${status}`,
          {createdBy}, {status}, true, 'admin-demo');
    }
  }
  await check('admin keeps existing ability to reopen an approved resolved report',
      {status: 'resuelto'}, {status: 'en_proceso'}, true, 'admin-demo');
  await check('admin state action does not bypass pending moderation',
      {moderationStatus: 'pendiente'}, {status: 'en_proceso'}, false, 'admin-demo');
  await check('admin state action does not bypass rejection',
      {moderationStatus: 'rechazado'}, {status: 'en_proceso'}, false, 'admin-demo');
  await check('invalid administrative state is blocked', {}, {status: 'invalid'}, false, 'admin-demo');
  await check('admin moderation cannot impersonate another moderator',
      {moderationStatus: 'pendiente'},
      {moderationStatus: 'aprobado', moderationReason: null, moderatedBy: 'neighbor-a'},
      false, 'admin-demo', [], true, true);
  await check('admin moderation needs a server moderation timestamp',
      {moderationStatus: 'pendiente'},
      {moderationStatus: 'aprobado', moderationReason: null, moderatedBy: 'admin-demo'},
      false, 'admin-demo');
  await check('admin status needs a server timestamp', {}, {status: 'en_proceso'},
      false, 'admin-demo', [], false);
  await check('admin own content is still validated', {createdBy: 'admin-demo'},
      {title: ' '}, false, 'admin-demo');
  await t.test('same admin resolves, edits own resolved content, reopens and edits', async () => {
    const id = 'admin-resolve-reopen';
    await seed(id, report({createdBy: 'admin-demo', status: 'en_proceso'}));
    assert.equal((await edit(id, {status: 'resuelto'}, 'admin-demo')).status, 200);
    assert.equal((await request(`${base}/reports/${id}`)).body.fields.status.stringValue, 'resuelto');
    assert.equal((await edit(id, {title: 'Own resolved edit'}, 'admin-demo')).status, 200);
    const resolved = (await request(`${base}/reports/${id}`)).body.fields;
    assert.equal(resolved.title.stringValue, 'Own resolved edit');
    assert.equal(resolved.status.stringValue, 'resuelto');
    assert.equal((await edit(id, {status: 'en_proceso'}, 'admin-demo')).status, 200);
    assert.equal((await edit(id, {title: 'Own reopened edit'}, 'admin-demo')).status, 200);
    const stored = await request(`${base}/reports/${id}`);
    assert.equal(stored.body.fields.title.stringValue, 'Own reopened edit');
    assert.equal(stored.body.fields.status.stringValue, 'en_proceso');
    assert.equal(stored.body.fields.createdBy.stringValue, 'admin-demo');
  });

  let dependencySerial = 0;
  for (const marker of [null, false, true]) {
    await t.test(`new report deletion marker ${marker}: only absent/false allowed`, async () => {
      const id = `create-with-marker-${String(marker)}`;
      const result = await request(`${base}/reports/${id}`, {method: 'PATCH', uid: 'neighbor-a',
        data: {fields: fields(report({moderationStatus: 'pendiente', status: 'pendiente',
          ...(marker === null ? {} : {deletionInProgress: marker})}))},
      });
      assert.equal(result.status, marker === true ? 403 : 200, JSON.stringify(result.body));
    });
  }
  async function contribute(id, kind, patch, uid) {
    const name = `projects/${project}/databases/(default)/documents/reports/${id}/${kind}/dependency-${++dependencySerial}`;
    const result = await request(`${base}:commit`, {
      method: 'POST', uid, data: {writes: [{
        update: {name, fields: fields(patch)}, currentDocument: {exists: false},
        updateTransforms: [{fieldPath: 'createdAt', setToServerValue: 'REQUEST_TIME'}],
      }]},
    });
    return {result, route: `${base}/reports/${id}/${kind}/dependency-${dependencySerial}`};
  }
  async function checkComment(label, extra, allowed, uid = 'neighbor-a', patch = {}) {
    await t.test(label, async () => {
      const id = `comment-${++serial}`;
      await seed(id, report({status: 'resuelto', ...extra}));
      const {result, route} = await contribute(id, 'comments', {
        authorId: uid, authorName: 'Demo User', text: 'Demo follow-up', ...patch,
      }, uid);
      assert.equal(result.status, allowed ? 200 : 403, JSON.stringify(result.body));
      assert.equal((await request(route)).status, allowed ? 200 : 404);
    });
  }
  for (const uid of ['neighbor-a', 'neighbor-b', 'admin-demo']) {
    await checkComment(`${uid} comments on resolved approved report`, {}, true, uid);
  }
  for (const status of ['pendiente', 'en_revision', 'en_proceso']) {
    await checkComment(`approved ${status} comments remain enabled`, {status}, true);
  }
  for (const extra of [{moderationStatus: 'pendiente'}, {moderationStatus: 'rechazado'},
    {status: 'rechazado'}, {deletionInProgress: true}]) {
    for (const uid of ['neighbor-a', 'admin-demo']) {
      await checkComment(`comments blocked for ${uid}: ${JSON.stringify(extra)}`, extra, false, uid);
    }
  }
  await checkComment('unapproved user cannot comment on resolved report', {}, false, 'unapproved');
  await checkComment('unauthenticated user cannot comment', {}, false, null);
  await checkComment('comment cannot impersonate another user', {}, false, 'neighbor-a', {authorId: 'neighbor-b'});
  await checkComment('empty comment denied', {}, false, 'neighbor-a', {text: ''});
  await checkComment('oversized comment denied', {}, false, 'neighbor-a', {text: 'x'.repeat(1001)});
  await t.test('missing parent never accepts a comment', async () => {
    const {result, route} = await contribute('missing-parent', 'comments',
        {authorId: 'admin-demo', text: 'Blocked orphan'}, 'admin-demo');
    assert.equal(result.status, 403, JSON.stringify(result.body));
    assert.equal((await request(route)).status, 404);
  });
  await t.test('resolved report still rejects new photo metadata', async () => {
    const id = 'closed-no-new-photos';
    await seed(id, report({status: 'resuelto'}));
    const {result} = await contribute(id, 'photos', {uploadedBy: 'admin-demo'}, 'admin-demo');
    assert.equal(result.status, 403, JSON.stringify(result.body));
  });
  await check('resident cannot lock a resolved report', {status: 'resuelto'},
      {deletionInProgress: true}, false);
  await check('admin cannot lock an active report', {},
      {deletionInProgress: true}, false, 'admin-demo');
  await check('admin can start deletion of resolved report', {status: 'resuelto'},
      {deletionInProgress: true}, true, 'admin-demo');
  await check('admin can retry a locked deletion', {status: 'resuelto', deletionInProgress: true},
      {deletionInProgress: true}, true, 'admin-demo');
  await check('locked report cannot be reopened mid-deletion',
      {status: 'resuelto', deletionInProgress: true}, {status: 'en_proceso'}, false, 'admin-demo');
  await check('locked report cannot have its content changed',
      {status: 'resuelto', createdBy: 'admin-demo', deletionInProgress: true}, {title: 'Blocked'}, false, 'admin-demo');
  await check('locked report cannot be moderated to bypass its state',
      {status: 'resuelto', deletionInProgress: true},
      {moderationStatus: 'rechazado', moderationReason: 'Demo', moderatedBy: 'admin-demo'},
      false, 'admin-demo', [], true, true);
  await check('lock cannot be cleared while dependencies are being purged',
      {status: 'resuelto', deletionInProgress: true}, {deletionInProgress: false}, false, 'admin-demo');
  await t.test('delete lock closes the comment-to-parent-deletion race', async () => {
    const id = 'comment-delete-race';
    await seed(id, report({status: 'resuelto'}));
    const previous = await contribute(id, 'comments', {authorId: 'neighbor-a', text: 'Before lock'}, 'neighbor-a');
    assert.equal(previous.result.status, 200);
    const unguarded = await request(`${base}/reports/${id}`, {method: 'DELETE', uid: 'admin-demo'});
    assert.equal(unguarded.status, 403);
    assert.equal((await edit(id, {deletionInProgress: true}, 'admin-demo')).status, 200);
    assert.equal((await contribute(id, 'comments', {authorId: 'neighbor-a', text: 'After lock'}, 'neighbor-a')).result.status, 403);
    const purge = await request(previous.route, {method: 'DELETE', uid: 'admin-demo'});
    assert.equal(purge.status, 200, JSON.stringify(purge.body));
    const removed = await request(`${base}/reports/${id}`, {method: 'DELETE', uid: 'admin-demo'});
    assert.equal(removed.status, 200, JSON.stringify(removed.body));
    const late = await contribute(id, 'comments', {authorId: 'admin-demo', text: 'After deletion'}, 'admin-demo');
    assert.equal(late.result.status, 403);
    assert.equal((await request(late.route)).status, 404);
    assert.equal((await request(previous.route)).status, 404);
  });
});
