// Fictional profiles and local services only. No production calls.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {fixture, HttpsError} = require('./helpers/identity_fixture.cjs');
const source = fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8');
const handlerSource = source.slice(source.indexOf('exports.setUserRole ='), source.indexOf('exports.updateOwnProfile ='));
const profile = (role = 'admin', extra = {}) => ({nombre: 'Fictional Member', email: 'member@example.com',
  role, approvalStatus: 'aprobado', dni: '00000001', ...extra});
const request = (actor, target, role = 'vecino') => ({auth: {uid: actor}, data: {userId: target, role}});
function setup(members = [['a', profile()], ['b', profile()]]) {
  const f = fixture({members});
  const claims = new Map(members.map(([uid]) => [uid, {customFlag: true, approved: true, role: f.data.users.get(uid).role}]));
  const writes = [];
  const auth = {getUser: async uid => ({uid, customClaims: claims.get(uid)}),
    setCustomUserClaims: async (uid, value) => {claims.set(uid, {...value}); writes.push({uid, ...value});}};
  const context = {exports: {}, onCall: (_, callback) => callback, region: 'local', HttpsError,
    getFirestore: () => f.db, getAuth: () => auth, FieldValue: {serverTimestamp: () => 'server-time'},
    requireAdmin: async auth => {
      if (!auth?.uid) throw new HttpsError('unauthenticated', 'Login required');
      const actor = f.data.users.get(auth.uid);
      if (actor?.role !== 'admin' || actor.approvalStatus !== 'aprobado') throw new HttpsError('permission-denied', 'Admin required');
    }};
  vm.runInNewContext(handlerSource, context);
  return {...f, auth, claims, writes, context, change: context.exports.setUserRole};
}

test('two simultaneous mutual demotions leave one admin and matching claims', async () => {
  for (const reverse of [false, true]) {
    const f = setup();
    const calls = [request('a', 'b'), request('b', 'a')];
    if (reverse) calls.reverse();
    const results = await Promise.allSettled(calls.map(f.change));
    assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
    assert.equal(results.find(r => r.status === 'rejected').reason.code, 'permission-denied');
    assert.equal([...f.data.users.values()].filter(p => p.role === 'admin').length, 1);
    for (const uid of ['a', 'b']) assert.equal(f.claims.get(uid).role, f.data.users.get(uid).role);
    assert.equal(f.writes.length, 1);
  }
});

test('caller privileges are rechecked inside the transaction, not only before it', async () => {
  const f = setup();
  const run = f.db.runTransaction;
  f.db.runTransaction = callback => {f.data.users.set('a', profile('vecino')); return run(callback);};
  await assert.rejects(f.change(request('a', 'b')), {code: 'permission-denied'});
  assert.equal(f.data.users.get('b').role, 'admin');
  assert.equal(f.writes.length, 0);
});

test('no self-demotion, anonymous requests or invalid roles; neighbors cannot change roles', async () => {
  const f = setup([['a', profile()], ['b', profile('vecino')]]);
  await assert.rejects(f.change(request('a', 'a')), {code: 'failed-precondition'});
  await assert.rejects(f.change({data: {userId: 'b', role: 'admin'}}), {code: 'unauthenticated'});
  await assert.rejects(f.change(request('b', 'a')), {code: 'permission-denied'});
  await assert.rejects(f.change(request('a', 'b', 'owner')), {code: 'invalid-argument'});
  assert.equal(f.writes.length, 0);
  assert.equal(f.data.users.get('a').role, 'admin');
});

test('normal promotion and demotion preserve custom claims and unrelated profile fields', async () => {
  const f = setup([['a', profile()], ['b', profile('vecino', {address: 'Fictional location'})]]);
  await f.change(request('a', 'b', 'admin'));
  assert.equal(f.data.users.get('b').role, 'admin');
  await f.change(request('a', 'b', 'vecino'));
  assert.equal(f.data.users.get('b').address, 'Fictional location');
  assert.equal(f.claims.get('b').customFlag, true);
  assert.equal(f.claims.get('b').role, 'vecino');
});

test('missing, unapproved or withdrawing targets are not updated', async () => {
  for (const target of [null, profile('vecino', {approvalStatus: 'rechazado'}),
    profile('vecino', {profileWithdrawalInProgress: true})]) {
    const f = setup(target ? [['a', profile()], ['b', target]] : [['a', profile()]]);
    await assert.rejects(f.change(request('a', 'b', 'admin')),
      {code: target?.profileWithdrawalInProgress ? 'failed-precondition' : 'not-found'});
    assert.equal(f.writes.length, 0);
  }
});

test('transaction failure never updates claims', async () => {
  const f = setup();
  f.db.runTransaction = async () => {throw Error('Simulated transaction failure');};
  await assert.rejects(f.change(request('a', 'b')), /Simulated transaction failure/);
  assert.equal(f.writes.length, 0);
  assert.equal(f.data.users.get('b').role, 'admin');
});

test('claims failure never undoes the committed demotion and an explicit retry repairs it', async () => {
  const f = setup();
  const write = f.auth.setCustomUserClaims;
  f.auth.setCustomUserClaims = async () => {throw Error('Simulated Auth outage');};
  await assert.rejects(f.change(request('a', 'b')), {code: 'internal'});
  assert.equal(f.data.users.get('b').role, 'vecino');
  assert.equal(f.data.users.get('a').role, 'admin');
  f.auth.setCustomUserClaims = write;
  await f.change(request('a', 'b'));
  assert.equal(f.claims.get('b').role, 'vecino');
});

test('a superseding change is reconciled instead of restoring stale claims', async () => {
  const f = setup();
  const write = f.auth.setCustomUserClaims;
  let first = true;
  f.auth.setCustomUserClaims = async (uid, claims) => {
    if (first) {first = false; f.data.users.set(uid, profile('admin'));}
    await write(uid, claims);
  };
  await f.change(request('a', 'b'));
  assert.equal(f.claims.get('b').role, 'admin');
  assert.equal(f.data.users.get('b').role, 'admin');
  assert.equal(f.writes.length, 2);
});
