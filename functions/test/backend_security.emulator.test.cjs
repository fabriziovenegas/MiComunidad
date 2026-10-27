// Real REST requests to local Firebase emulators. No Flutter or production access.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const project = 'demo-micomunidad-backend-security';
const hosts = {
  firestore: process.env.FIRESTORE_EMULATOR_HOST,
  auth: process.env.FIREBASE_AUTH_EMULATOR_HOST,
  storage: process.env.FIREBASE_STORAGE_EMULATOR_HOST,
  functions: process.env.FUNCTIONS_EMULATOR_HOST,
};
for (const host of Object.values(hosts)) {
  if (host && !/^127\.0\.0\.1:\d+$/.test(host)) throw Error('Loopback emulators required');
}
const enabled = Object.values(hosts).every(Boolean);
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a0VkAAAAASUVORK5CYII=', 'base64');
const pdf = Buffer.from('%PDF-1.4\n1 0 obj <</Type /Catalog>> endobj\ntrailer <</Root 1 0 R>>\n%%EOF');

test('closed backend permissions, schemas and attachment ownership via direct APIs', {skip: !enabled}, async t => {
  process.env.STORAGE_EMULATOR_HOST = `http://${hosts.storage}`;
  const {initializeApp, deleteApp} = require('firebase-admin/app');
  const {getFirestore} = require('firebase-admin/firestore');
  const {getAuth} = require('firebase-admin/auth');
  const {getStorage} = require('firebase-admin/storage');
  const bucketName = `${project}.appspot.com`;
  const app = initializeApp({projectId: project, storageBucket: bucketName}, 'backend-security-local');
  const db = getFirestore(app), auth = getAuth(app), bucket = getStorage(app).bucket();
  const tokens = {};
  const base = `http://${hosts.firestore}/v1/projects/${project}/databases/(default)/documents`;
  const full = path => `projects/${project}/databases/(default)/documents/${path}`;
  async function reset() {
    for (const url of [`http://${hosts.firestore}/emulator/v1/projects/${project}/databases/(default)/documents`,
      `http://${hosts.auth}/emulator/v1/projects/${project}/accounts`]) {
      const response = await fetch(url, {method: 'DELETE', signal: AbortSignal.timeout(15000)});
      assert.equal(response.status, 200);
      await response.text();
    }
    const [files] = await Promise.race([bucket.getFiles(), new Promise((_, reject) => {
      const timer = setTimeout(() => reject(Error('Timed out listing demo Storage bucket')), 15000);
      timer.unref();
    })]);
    for (const file of files) await file.delete();
  }
  await reset();
  t.after(async () => {await reset(); await db.terminate(); await deleteApp(app);});
  const headers = (actor, extra = {}) => ({...extra, ...(actor ? {Authorization: `Bearer ${tokens[actor]}`} : {})});
  async function result(response) {
    const text = await response.text();
    let body;
    try {body = JSON.parse(text);} catch (_) {body = text.slice(0, 300);}
    return {status: response.status, body};
  }
  const read = (path, actor) => fetch(`${base}/${path}`, {headers: headers(actor)}).then(result);
  const remove = (path, actor) => fetch(`${base}/${path}`, {method: 'DELETE', headers: headers(actor)}).then(result);
  function fields(data) {
    function value(x) {
      if (x === null) return {nullValue: null};
      if (typeof x === 'string') return {stringValue: x};
      if (typeof x === 'boolean') return {booleanValue: x};
      if (typeof x === 'number') return Number.isInteger(x) ? {integerValue: String(x)} : {doubleValue: x};
      if (x instanceof Date) return {timestampValue: x.toISOString()};
      if (Array.isArray(x)) return {arrayValue: {values: x.map(value)}};
      return {mapValue: {fields: fields(x)}};
    }
    return Object.fromEntries(Object.entries(data).map(([k, v]) => [k, value(v)]));
  }
  async function write(path, data, actor, {create = true, times = create ? ['createdAt', 'updatedAt'] : ['updatedAt'], deleted = []} = {}) {
    const response = await fetch(`${base}:commit`, {method: 'POST', headers: headers(actor, {'Content-Type': 'application/json'}),
      body: JSON.stringify({writes: [{update: {name: full(path), fields: fields(data)},
        ...(!create ? {updateMask: {fieldPaths: [...Object.keys(data), ...deleted]}} : {}),
        currentDocument: {exists: !create},
        updateTransforms: times.map(fieldPath => ({fieldPath, setToServerValue: 'REQUEST_TIME'}))}]}),
    });
    return result(response);
  }
  async function callable(name, data, actor) {
    return result(await fetch(`http://${hosts.functions}/${project}/southamerica-east1/${name}`, {
      method: 'POST', headers: headers(actor, {'Content-Type': 'application/json'}), body: JSON.stringify({data}),
      signal: AbortSignal.timeout(60000),
    }));
  }
  async function upload(path, actor, {mime = 'image/png', bytes = png, metadata = {uploadedBy: actor, attachmentUploadId: path.split('/').at(-1).split('_')[0]}} = {}) {
    const boundary = 'fictional-emulator-boundary';
    const body = Buffer.concat([Buffer.from(`--${boundary}\r\nContent-Type: application/json; charset=utf-8\r\n\r\n${JSON.stringify({name: path, contentType: mime, metadata})}\r\n--${boundary}\r\nContent-Type: ${mime}\r\n\r\n`), bytes, Buffer.from(`\r\n--${boundary}--\r\n`)]);
    return result(await fetch(`http://${hosts.storage}/v0/b/${bucketName}/o?name=${encodeURIComponent(path)}`, {
      method: 'POST', headers: headers(actor, {'Content-Type': `multipart/related; boundary=${boundary}`, 'X-Goog-Upload-Protocol': 'multipart'}), body,
    }));
  }
  async function fileRequest(path, actor, method = 'GET') {
    return result(await fetch(`http://${hosts.storage}/v0/b/${bucketName}/o/${encodeURIComponent(path)}`, {method, headers: headers(actor)}));
  }
  const allowed = response => assert.equal(response.status, 200, JSON.stringify(response.body));
  const denied = response => assert.ok([400, 401, 403].includes(response.status), JSON.stringify(response));
  const profile = (name, role = 'vecino', approvalStatus = 'aprobado') => ({nombre: name, role, approvalStatus});
  for (const [uid, data] of [
    ['admin', profile('Fictional Admin', 'admin')], ['neighbor', profile('Fictional Neighbor')],
    ['other', profile('Fictional Other')], ['pending', profile('Fictional Pending', 'vecino', 'pendiente')],
    ['former', profile('Fictional Former', 'vecino', 'retirado')], ['demoted', profile('Fictional Demoted', 'admin')],
  ]) {
    await auth.createUser({uid, email: `${uid}@example.com`, password: 'fictional-password'});
    await auth.setCustomUserClaims(uid, {approved: true, role: data.role});
    await db.doc(`users/${uid}`).set(data);
    const login = await fetch(`http://${hosts.auth}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-local-key`, {
      method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({email: `${uid}@example.com`, password: 'fictional-password', returnSecureToken: true}),
    });
    assert.equal(login.status, 200);
    tokens[uid] = (await login.json()).idToken;
  }
  const anonymous = await fetch(`http://${hosts.auth}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-local-key`, {
    method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({returnSecureToken: true}),
  });
  assert.equal(anonymous.status, 200);
  const anon = await anonymous.json(); tokens.anonymous = anon.idToken;
  const projectData = {title: 'Fictional project', description: 'Improve the fictional meeting place.', location: '', progress: 20, status: 'en_proceso', isTrashed: false, createdBy: 'admin'};
  const reportData = {title: 'Fictional report', description: 'A fictional street light needs attention.', location: '', category: 'iluminacion', priority: 'media', createdBy: 'neighbor', createdByName: 'Fictional Neighbor', moderationStatus: 'pendiente', status: 'pendiente'};
  const eventData = {title: 'Fictional meeting', description: '', location: '', eventDate: new Date('2026-11-01T15:00:00Z'), createdBy: 'admin'};
  await db.doc('projects/p').set({...projectData, createdAt: new Date(), updatedAt: new Date()});
  await db.doc('projects/archived').set({...projectData, isTrashed: true, trashedAt: new Date()});
  await db.doc('reports/r').set({...reportData, moderationStatus: 'aprobado'});
  await db.doc('reports/hidden').set({...reportData});
  await db.doc('reports/resolved').set({...reportData, createdBy: 'admin', moderationStatus: 'aprobado', status: 'resuelto'});
  await db.doc('events/e').set(eventData);
  await db.doc('mapPoints/m').set({title: 'Fictional reference', latitude: 0, longitude: 0});
  await db.doc('notifications/n').set({userId: 'neighbor', message: 'Fictional message'});
  await db.doc('accessRequests/private').set({dni: '00000009', name: 'Private fictional applicant', status: 'pendiente'});

  for (const actor of [null, 'anonymous', 'pending', 'former']) {
    await t.test(`${actor || 'no session'} cannot read, create, edit or delete private content`, async () => {
      for (const path of ['projects/p', 'reports/r', 'events/e', 'users/neighbor', 'accessRequests/private', 'mapPoints/m', 'notifications/n']) {
        denied(await read(path, actor)); denied(await remove(path, actor));
        denied(await write(path, {title: 'Tampered'}, actor, {create: false}));
      }
      denied(await write(`reports/new-${actor || 'none'}`, reportData, actor));
      denied(await callable('getReportAuthorName', {reportId: 'r'}, actor));
      denied(await callable('getContentAuthorName', {collection: 'events', contentId: 'e'}, actor));
      denied(await callable('setUserRole', {userId: 'other', role: 'admin'}, actor));
      denied(await callable('updateOwnProfile', {nombre: 'Tampered'}, actor));
    });
  }
  await t.test('welcome summary and minimal DNI status remain public', async () => {
    const summary = await callable('getPublicCommunitySummary', {}, null); allowed(summary);
    assert.deepEqual(Object.keys(summary.body.result).sort(), ['activeMembers', 'projects']);
    const lookup = await callable('getAccessRequestStatus', {dni: '00000009'}, null); allowed(lookup);
    assert.deepEqual(Object.keys(lookup.body.result.request).sort(), ['createdAt', 'email', 'status']);
    assert.equal(lookup.body.result.request.name, undefined);
  });
  await t.test('approved neighbors read allowed content but cannot administer, read profiles or escalate', async () => {
    for (const path of ['projects/p', 'reports/r', 'events/e', 'mapPoints/m', 'notifications/n', 'users/neighbor']) allowed(await read(path, 'neighbor'));
    for (const path of ['users/other', 'accessRequests/private', 'projects/archived', 'notifications/missing-other']) denied(await read(path, 'neighbor'));
    denied(await write('users/neighbor', {role: 'admin'}, 'neighbor', {create: false}));
    denied(await write('users/neighbor', {nombre: 'Forged'}, 'neighbor', {create: false}));
    denied(await write('users/new-profile', {role: 'admin', approvalStatus: 'aprobado'}, 'neighbor'));
    denied(await write('projects/member-project', projectData, 'neighbor'));
    denied(await write('events/member-event', eventData, 'neighbor'));
    denied(await callable('setUserRole', {userId: 'neighbor', role: 'admin'}, 'neighbor'));
    denied(await callable('reviewAccessRequest', {requestId: 'private', action: 'approve'}, 'neighbor'));
    denied(await callable('updateOwnProfile', {role: 'admin', nombre: 'Forged'}, 'neighbor'));
  });
  await t.test('report creation, author editing, moderation, resolution and comments retain their normal rules', async () => {
    allowed(await write('reports/new-report', reportData, 'neighbor'));
    for (const [n, patch] of Object.entries({extra: {adminOnly: true}, badTitle: {title: ''}, badDescription: {description: ''}, badCategory: {category: 'admin'}, badPriority: {priority: 'urgent'}, wrongAuthor: {createdBy: 'other'}, forgedName: {createdByName: 'Fictional Admin'}, wrongType: {title: {}}, long: {title: 'x'.repeat(161)}})) {
      denied(await write(`reports/invalid-${n}`, {...reportData, ...patch}, 'neighbor'));
    }
    allowed(await write('reports/new-report', {title: 'Corrected fictional report'}, 'neighbor', {create: false}));
    denied(await write('reports/new-report', {title: 'Someone else'}, 'other', {create: false}));
    denied(await write('reports/new-report', {status: 'resuelto'}, 'neighbor', {create: false}));
    allowed(await write('reports/new-report', {moderationStatus: 'aprobado', moderationReason: null, moderatedBy: 'admin'}, 'admin', {create: false, times: ['moderatedAt', 'updatedAt']}));
    allowed(await write('reports/new-report', {status: 'resuelto'}, 'admin', {create: false}));
    denied(await write('reports/new-report', {title: 'Neighbor cannot edit resolved'}, 'neighbor', {create: false}));
    allowed(await write('reports/resolved', {title: 'Admin edits own resolved report'}, 'admin', {create: false}));
    allowed(await write('reports/resolved/comments/comment', {text: 'A fictional follow-up.', authorId: 'neighbor', authorName: 'Fictional Neighbor'}, 'neighbor', {times: ['createdAt']}));
  });
  await t.test('admin project and event workflows reject extra fields, forged creators and invalid types', async () => {
    allowed(await write('projects/new-project', projectData, 'admin'));
    allowed(await write('events/new-event', eventData, 'admin'));
    for (const patch of [{progress: -1}, {progress: 101}, {progress: 1.5}, {progress: '50'}, {status: 'unknown'}, {url: 'https://example.com/poison'}, {createdBy: 'neighbor'}]) denied(await write('projects/new-project', patch, 'admin', {create: false}));
    allowed(await write('projects/new-project', {progress: 100}, 'admin', {create: false}));
    denied(await remove('projects/new-project', 'admin'));
    allowed(await write('projects/new-project', {isTrashed: true}, 'admin', {create: false, times: ['trashedAt', 'updatedAt']}));
    allowed(await write('projects/new-project', {isTrashed: false}, 'admin', {create: false, deleted: ['trashedAt']}));
    denied(await write('events/new-event', {createdBy: 'neighbor'}, 'admin', {create: false}));
    denied(await write('events/new-event', {eventDate: 'tomorrow'}, 'admin', {create: false}));
    allowed(await write('events/new-event', {title: 'Updated fictional event'}, 'admin', {create: false}));
    await db.doc('projects/legacy').set({...projectData, description: 'x'.repeat(4001)});
    allowed(await write('projects/legacy', {isTrashed: true}, 'admin', {create: false, times: ['trashedAt', 'updatedAt']}));
    allowed(await write('projects/legacy', {isTrashed: false}, 'admin', {create: false, deleted: ['trashedAt']}));
    assert.equal((await db.doc('projects/legacy').get()).data().description.length, 4001);
    denied(await write('projects/legacy', {description: 'y'.repeat(4001)}, 'admin', {create: false}));
    await db.doc('events/legacy').set({...eventData, description: 'x'.repeat(4001)});
    allowed(await write('events/legacy', {title: 'Updated legacy event'}, 'admin', {create: false}));
  });
  await t.test('comments require a real parent, canonical author, closed fields and server date', async () => {
    for (const collection of ['projects', 'reports', 'events']) {
      const parent = collection === 'projects' ? 'p' : collection === 'reports' ? 'r' : 'e';
      const comment = {text: 'Fictional comment', authorId: 'neighbor', authorName: 'Fictional Neighbor'};
      allowed(await write(`${collection}/${parent}/comments/valid`, comment, 'neighbor', {times: ['createdAt']}));
      for (const patch of [{authorName: 'Fictional Admin'}, {authorId: 'admin'}, {text: ' '}, {url: 'https://example.com/poison'}, {text: {unexpected: 'object'}}]) {
        denied(await write(`${collection}/${parent}/comments/invalid`, {...comment, ...patch}, 'neighbor', {times: ['createdAt']}));
      }
      denied(await write(`${collection}/missing/comments/orphan`, comment, 'neighbor', {times: ['createdAt']}));
    }
  });

  const registration = (extra = {}) => ({collection: 'projects', documentId: 'p', kind: 'photos', attachmentId: 'upload', storagePath: 'projects/p/photos/upload_photo.png', name: 'photo.png', ...extra});
  await t.test('Storage requires current approval, existing parent, owner metadata and stable file identity', async () => {
    for (const actor of [null, 'anonymous', 'pending', 'former']) denied(await upload(`events/e/photos/no-${actor || 'session'}_photo.png`, actor));
    denied(await upload('events/missing/photos/orphan_photo.png', 'neighbor'));
    denied(await upload('projects/archived/photos/trash_photo.png', 'neighbor'));
    denied(await upload('reports/hidden/photos/foreign_photo.png', 'other'));
    denied(await upload('reports/resolved/photos/closed_photo.png', 'neighbor'));
    denied(await upload('projects/p/photos/forged_photo.png', 'neighbor', {metadata: {uploadedBy: 'admin', attachmentUploadId: 'forged'}}));
    denied(await upload('projects/p/photos/wrong_photo.png', 'neighbor', {metadata: {uploadedBy: 'neighbor', attachmentUploadId: 'different'}}));
    allowed(await upload('projects/p/photos/upload_photo.png', 'neighbor'));
    denied(await upload('projects/p/photos/upload_photo.png', 'other'));
    for (const actor of [null, 'anonymous', 'pending', 'former']) denied(await fileRequest('projects/p/photos/upload_photo.png', actor));
    allowed(await fileRequest('projects/p/photos/upload_photo.png', 'other'));
    denied(await fileRequest('projects/p/photos/upload_photo.png', 'other', 'DELETE'));
    denied(await fileRequest('projects/p/photos/upload_photo.png', 'neighbor', 'DELETE'));
  });
  await t.test('attachment documents cannot be published directly; callable verifies object and ignores no supplied URL', async subtest => {
    const oldToken = (await bucket.file('projects/p/photos/upload_photo.png').getMetadata())[0].metadata.firebaseStorageDownloadTokens;
    denied(await write('projects/p/photos/poison', {uploadedBy: 'neighbor', url: 'https://example.com/poison', storagePath: 'events/e/photos/other.png'}, 'neighbor', {times: ['createdAt']}));
    denied(await write('projects/p/photos/poison', {uploadedBy: 'admin', url: 'https://example.com/poison'}, 'admin', {times: ['createdAt']}));
    for (const patch of [{url: 'https://example.com/poison'}, {uploadedBy: 'admin'}, {storagePath: 'events/e/photos/upload_photo.png'}, {storagePath: 'projects/p/photos/../other.png'}, {name: 'photo.pdf'}, {attachmentId: 'other'}]) denied(await callable('registerContentAttachment', registration(patch), 'neighbor'));
    denied(await callable('registerContentAttachment', registration(), 'other'));
    allowed(await callable('registerContentAttachment', registration(), 'neighbor'));
    const original = (await db.doc('projects/p/photos/upload').get()).data();
    denied(await remove('projects/p/photos/upload', 'neighbor'));
    allowed(await result(await fetch(`http://${hosts.storage}/v0/b/${bucketName}/o/${encodeURIComponent(original.storagePath)}?alt=media`, {headers: headers('neighbor')})));
    denied(await result(await fetch(`http://${hosts.storage}/v0/b/${bucketName}/o/${encodeURIComponent(original.storagePath)}?alt=media`)));
    assert.equal(original.uploadedBy, 'neighbor');
    assert.equal(original.storagePath, 'projects/p/photos/upload_photo.png');
    assert.equal(original.url, `gs://${bucketName}/${original.storagePath}`);
    // The official emulator keeps downloadTokens in a separate array and does
    // not implement GCS's null metadata-key deletion. Do not pretend that its
    // successful PATCH proves real token revocation. Test the real GCS request
    // contract separately and explicitly mark this emulator limitation.
    await subtest.test('GCS token deletion invalidates the old bearer URL', {skip:
      'Storage emulator does not remove its separate downloadTokens array on metadata null deletion'}, async () => {
      assert.ok(!(await bucket.file(original.storagePath).getMetadata())[0].metadata.firebaseStorageDownloadTokens);
      denied(await result(await fetch(`http://${hosts.storage}/v0/b/${bucketName}/o/${encodeURIComponent(original.storagePath)}?alt=media&token=${oldToken}`)));
    });
    allowed(await callable('registerContentAttachment', registration(), 'neighbor'));
    assert.deepEqual((await db.doc('projects/p/photos/upload').get()).data(), original);
  });
  await t.test('spoofed MIME and oversized uploads cannot become shared attachments', async () => {
    allowed(await upload('events/e/photos/fake_photo.png', 'neighbor', {bytes: Buffer.from('<html>not an image</html>')}));
    denied(await callable('registerContentAttachment', registration({collection: 'events', documentId: 'e', attachmentId: 'fake', storagePath: 'events/e/photos/fake_photo.png'}), 'neighbor'));
    denied(await upload('events/e/photos/svg_photo.svg', 'neighbor', {mime: 'image/svg+xml'}));
    denied(await upload('events/e/minutes/large_minutes.pdf', 'neighbor', {mime: 'application/pdf', bytes: Buffer.alloc(5 * 1024 * 1024 + 1)}));
    allowed(await upload('events/e/minutes/minutes_minutes.pdf', 'neighbor', {mime: 'application/pdf', bytes: pdf}));
    allowed(await callable('registerContentAttachment', registration({collection: 'events', documentId: 'e', kind: 'minutes', attachmentId: 'minutes', storagePath: 'events/e/minutes/minutes_minutes.pdf', name: 'minutes.pdf'}), 'neighbor'));
  });
  await t.test('old administrator/member tokens lose access when the canonical profile changes', async () => {
    await db.doc('users/demoted').update({role: 'vecino'});
    denied(await write('projects/token-admin', projectData, 'demoted'));
    denied(await fileRequest('projects/p/photos/upload_photo.png', 'demoted', 'DELETE'));
    await db.doc('users/former').update({approvalStatus: 'aprobado', profileWithdrawalInProgress: true});
    denied(await fileRequest('projects/p/photos/upload_photo.png', 'former'));
    denied(await remove('reports/resolved/comments/comment', 'former'));
    await db.doc('users/neighbor').update({approvalStatus: 'retirado'});
    denied(await fileRequest('projects/p/photos/upload_photo.png', 'neighbor'));
    denied(await callable('deleteContentAttachment', {collection: 'projects', documentId: 'p', kind: 'photos', attachmentId: 'upload'}, 'neighbor'));
    await db.doc('users/neighbor').update({approvalStatus: 'aprobado'});
  });
  await t.test('deletion derives its object from the verified record and cannot target unrelated paths', async () => {
    const target = {collection: 'projects', documentId: 'p', kind: 'photos', attachmentId: 'upload'};
    denied(await callable('deleteContentAttachment', {...target, storagePath: 'events/e/minutes/minutes_minutes.pdf'}, 'admin'));
    denied(await callable('deleteContentAttachment', target, 'other'));
    await db.doc('projects/p/photos/legacy-poison').set({uploadedBy: 'neighbor', storagePath: 'events/e/minutes/minutes_minutes.pdf'});
    const poison = await callable('deleteContentAttachment', {...target, attachmentId: 'legacy-poison'}, 'admin');
    assert.equal(poison.body.error.status, 'FAILED_PRECONDITION');
    assert.equal((await bucket.file('events/e/minutes/minutes_minutes.pdf').exists())[0], true);
    allowed(await callable('deleteContentAttachment', target, 'neighbor'));
    assert.equal((await bucket.file('projects/p/photos/upload_photo.png').exists())[0], false);
    assert.equal((await db.doc('projects/p/photos/upload').get()).exists, false);
  });
  await t.test('profile changes use the approved self-service endpoint and reject administrative or URL fields', async () => {
    const data = {nombre: 'Fictional Updated Neighbor', dni: '00000006', phone: '000000001',
      email: 'neighbor@example.com', address: 'Fictional address', timeLivingHere: '1 a 5 años', reason: 'Fictional reason'};
    for (const patch of [{userId: 'other'}, {role: 'admin'}, {approvalStatus: 'aprobado'}, {photoUrl: 'https://example.com/poison'}, {phone: {unexpected: 'object'}}, {timeLivingHere: 'invented'}]) {
      denied(await callable('updateOwnProfile', {...data, ...patch}, 'neighbor'));
    }
    allowed(await callable('updateOwnProfile', data, 'neighbor'));
    assert.equal((await db.doc('users/neighbor').get()).data().nombre, data.nombre);
    assert.equal((await db.doc('users/neighbor').get()).data().role, 'vecino');
    assert.equal((await db.doc('users/other').get()).data().nombre, 'Fictional Other');
  });
  await t.test('anonymous access request and public status remain usable without neighboring access', async () => {
    const documentPath = `access_requests/${anon.localId}/identity/document.pdf`;
    allowed(await upload(documentPath, 'anonymous', {mime: 'application/pdf', bytes: pdf, metadata: {uploadedBy: anon.localId}}));
    denied(await upload(`access_requests/another-person/identity/document.pdf`, 'anonymous', {mime: 'application/pdf', bytes: pdf, metadata: {uploadedBy: anon.localId}}));
    const data = {requestId: 'public-request', name: 'Fictional Applicant', dni: '00000001', phone: '000000001', email: 'applicant@example.com', address: 'Fictional address', timeLivingHere: '1 a 5 años', reason: 'Fictional request', identityDocumentPath: documentPath};
    denied(await callable('submitAccessRequest', {...data, role: 'admin'}, 'anonymous'));
    denied(await callable('submitAccessRequest', {...data, identityDocumentUrl: 'https://example.com/poison'}, 'anonymous'));
    allowed(await callable('submitAccessRequest', data, 'anonymous'));
    allowed(await callable('submitAccessRequest', data, 'anonymous'));
    const request = (await db.doc('accessRequests/public-request').get()).data();
    assert.equal(request.status, 'pendiente'); assert.equal(request.role, undefined);
    denied(await read('accessRequests/public-request', 'anonymous'));
    const visible = await callable('getAccessRequestStatus', {dni: '00000001'}, null); allowed(visible);
    assert.deepEqual(Object.keys(visible.body.result.request).sort(), ['createdAt', 'email', 'status']);
    assert.ok(visible.body.result.request.email.includes('*'));
    const signup = await fetch(`http://${hosts.auth}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-local-key`, {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({email: data.email, password: 'fictional-external-password', returnSecureToken: true}),
    });
    assert.equal(signup.status, 200);
    const external = await signup.json();
    const before = (await auth.getUser(external.localId)).toJSON();
    const approval = await callable('reviewAccessRequest', {requestId: data.requestId, action: 'approve'}, 'admin');
    assert.equal(approval.body.error.status, 'ALREADY_EXISTS');
    assert.equal((await db.doc(`users/${external.localId}`).get()).exists, false);
    assert.equal((await db.doc(`accessRequests/${data.requestId}`).get()).data().status, 'pendiente');
    assert.deepEqual((await auth.getUser(external.localId)).toJSON(), before);
  });
  await t.test('unused legacy password-code handlers cannot perform public account operations', async () => {
    for (const name of ['requestPasswordResetCode', 'confirmPasswordResetCode']) {
      const response = await callable(name, {email: 'neighbor@example.com', code: '123456', newPassword: 'fictional-other-password'}, null);
      assert.equal(response.body.error.status, 'FAILED_PRECONDITION');
    }
  });
  await t.test('legacy link maintenance has a dry run and preserves files', async () => {
    const path = 'events/e/photos/legacy_photo.png';
    const created = await upload(path, 'neighbor'); allowed(created);
    const token = created.body.downloadTokens;
    const url = `http://${hosts.storage}/v0/b/${bucketName}/o/${encodeURIComponent(path)}?alt=media&token=${token}`;
    assert.equal((await fetch(url)).status, 200);
    const {revokeLegacyDownloadTokens} = require('../download_token_cleanup');
    const count = (await bucket.getFiles())[0].length;
    const dry = await revokeLegacyDownloadTokens({bucket});
    assert.equal(dry.dryRun, true); assert.equal(dry.revocationRequests, 0);
    assert.equal((await fetch(url)).status, 200);
    const applied = await revokeLegacyDownloadTokens({bucket, apply: true});
    assert.ok(applied.revocationRequests > 0);
    // Null-key deletion is unit-tested; HTTP revocation needs a real disposable
    // Storage object after separate authorization, due to the emulator gap above.
    allowed(await fileRequest(path, 'neighbor'));
    assert.equal((await bucket.getFiles())[0].length, count);
  });
});
