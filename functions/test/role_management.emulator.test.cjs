// Fixed demo project and loopback emulators only. No production credentials.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const host = process.env.FIRESTORE_EMULATOR_HOST;
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const project = 'demo-micomunidad-role-management';
for (const value of [host, authHost]) {
  if (value && !/^127\.0\.0\.1:\d+$/.test(value)) throw Error('Loopback emulators required');
}

test('role changes protect the last administrator in official emulators', {skip: !host || !authHost}, async t => {
  const {initializeApp, deleteApp} = require('firebase-admin/app');
  const {getFirestore, FieldValue} = require('firebase-admin/firestore');
  const {getAuth} = require('firebase-admin/auth');
  const {HttpsError} = require('firebase-functions/v2/https');
  const app = initializeApp({projectId: project}, 'role-management-local-test');
  const db = getFirestore(app), auth = getAuth(app);
  const reset = async () => {
    for (const url of [`http://${host}/emulator/v1/projects/${project}/databases/(default)/documents`,
      `http://${authHost}/emulator/v1/projects/${project}/accounts`]) {
      assert.equal((await fetch(url, {method: 'DELETE'})).status, 200);
    }
  };
  t.after(async () => {await reset(); await db.terminate(); await deleteApp(app);});
  const source = fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8');
  // The SDK checks instanceof Promise. Bridge VM callbacks back into the host
  // realm without changing the transaction's reads, writes or retry behavior.
  const database = {collection: db.collection.bind(db),
    runTransaction: callback => db.runTransaction(async transaction => callback(transaction))};
  const context = {exports: {}, onCall: (_, callback) => callback, region: 'local', HttpsError,
    getFirestore: () => database, getAuth: () => auth, FieldValue};
  vm.runInNewContext(source.slice(source.indexOf('async function requireAdmin'), source.indexOf('function clean')), context);
  vm.runInNewContext(source.slice(source.indexOf('exports.setUserRole ='), source.indexOf('exports.updateOwnProfile =')), context);
  const change = (actor, target, role = 'vecino') => context.exports.setUserRole({
    auth: {uid: actor, token: {approved: true, role: 'admin'}}, data: {userId: target, role},
  });
  async function seed(members) {
    await reset();
    for (const [uid, role] of members) {
      await auth.createUser({uid, email: `${uid}@example.com`, displayName: 'Fictional Member'});
      await auth.setCustomUserClaims(uid, {approved: true, role, customFlag: true});
      await db.doc(`users/${uid}`).set({nombre: 'Fictional Member', email: `${uid}@example.com`,
        role, approvalStatus: 'aprobado', unchangedField: 'Fictional data'});
    }
  }
  async function verifyClaims(uids) {
    for (const uid of uids) {
      const profile = (await db.doc(`users/${uid}`).get()).data();
      const account = await auth.getUser(uid);
      assert.equal(account.customClaims.role, profile.role);
      assert.equal(account.customClaims.approved, true);
      assert.equal(account.customClaims.customFlag, true);
      assert.equal(profile.unchangedField, 'Fictional data');
    }
  }
  const admins = async () => (await db.collection('users').where('role', '==', 'admin')
    .where('approvalStatus', '==', 'aprobado').get()).size;

  await t.test('mutual demotions have exactly one winner, across six concurrent runs', async () => {
    for (let n = 0; n < 6; n++) {
      await seed([['a', 'admin'], ['b', 'admin']]);
      const calls = n % 2 ? [['b', 'a'], ['a', 'b']] : [['a', 'b'], ['b', 'a']];
      const results = await Promise.allSettled(calls.map(([actor, target]) => change(actor, target)));
      assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
      assert.equal(results.find(r => r.status === 'rejected').reason.code, 'permission-denied');
      assert.equal(await admins(), 1);
      await verifyClaims(['a', 'b']);
      const loser = (await db.doc('users/a').get()).data().role === 'vecino' ? 'a' : 'b';
      const winner = loser === 'a' ? 'b' : 'a';
      // Even an old token claiming admin cannot authorize the demoted actor.
      await assert.rejects(change(loser, winner), {code: 'permission-denied'});
      assert.equal(await admins(), 1);
    }
  });

  await t.test('one remaining admin cannot demote themself but can appoint another', async () => {
    await seed([['a', 'admin'], ['b', 'vecino']]);
    await assert.rejects(change('a', 'a'), {code: 'failed-precondition'});
    assert.equal(await admins(), 1);
    await change('a', 'b', 'admin');
    assert.equal(await admins(), 2);
    await change('b', 'a');
    assert.equal(await admins(), 1);
    await verifyClaims(['a', 'b']);
  });

  await t.test('one administrator may demote two others concurrently while retaining access', async () => {
    await seed([['a', 'admin'], ['b', 'admin'], ['c', 'admin']]);
    await Promise.all([change('a', 'b'), change('a', 'c')]);
    assert.equal(await admins(), 1);
    assert.equal((await db.doc('users/a').get()).data().role, 'admin');
    await verifyClaims(['a', 'b', 'c']);
  });

  await t.test('three simultaneous cyclic demotions never remove every administrator', async () => {
    await seed([['a', 'admin'], ['b', 'admin'], ['c', 'admin']]);
    const results = await Promise.allSettled([change('a', 'b'), change('b', 'c'), change('c', 'a')]);
    assert.ok(results.some(r => r.status === 'fulfilled'));
    assert.ok(results.some(r => r.status === 'rejected'));
    assert.ok(await admins() >= 1);
    await verifyClaims(['a', 'b', 'c']);
  });

  await t.test('concurrent opposite changes to one target finish with matching Auth claims', async () => {
    for (let n = 0; n < 4; n++) {
      await seed([['a', 'admin'], ['b', 'admin'], ['c', 'vecino']]);
      await Promise.all([change('a', 'c', 'admin'), change('b', 'c', 'vecino')]);
      assert.ok(await admins() >= 2);
      await verifyClaims(['a', 'b', 'c']);
    }
  });

  await t.test('revocation after the initial check is rejected again inside the transaction', async () => {
    await seed([['a', 'admin'], ['b', 'admin']]);
    context.getFirestore = () => ({collection: db.collection.bind(db), runTransaction: async callback => {
      await db.doc('users/a').update({role: 'vecino'});
      return db.runTransaction(async transaction => callback(transaction));
    }});
    try {
      await assert.rejects(change('a', 'b'), {code: 'permission-denied'});
      assert.equal((await db.doc('users/b').get()).data().role, 'admin');
      assert.equal(await admins(), 1);
    } finally {context.getFirestore = () => database;}
  });
});
