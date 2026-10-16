const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {fixture: identityFixture} = require('./helpers/identity_fixture.cjs');
const {createProfileIdentity, profileSnapshot} = require('../profile_identity');

const source = fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8');

function fixture({requests = [], members = [], failBatch = false, missingAuth = false} = {}) {
  const base = identityFixture({members, requests});
  const {data} = base;
  const batchSizes = [];
  let authDeletes = 0;
  class HttpsError extends Error {
    constructor(code, message) { super(message); this.code = code; }
  }
  const context = {
    profileSnapshot,
    exports: {}, region: 'local', HttpsError,
    onCall: (_, callback) => callback,
    requireAdmin: async (auth) => { if (auth?.uid !== 'admin') throw new HttpsError('permission-denied', 'admin only'); },
    FieldValue: {serverTimestamp: () => 'timestamp'},
    console: {error: () => {}},
    getAuth: () => ({deleteUser: async () => {
      authDeletes++;
      if (missingAuth) { const error = new Error('missing'); error.code = 'auth/user-not-found'; throw error; }
    }}),
    getFirestore: () => ({
      ...base.db,
      batch: () => {
        const updates = [];
        return {
          update: (ref, values) => updates.push([ref, values]),
          commit: async () => {
            if (failBatch) throw new Error('simulated failure');
            batchSizes.push(updates.length);
            for (const [ref, values] of updates) Object.assign(data[ref.collection].get(ref.id), values);
          },
        };
      },
    }),
  };
  context.profileIdentity = () => createProfileIdentity({firestore: context.getFirestore(),
    auth: context.getAuth(), HttpsError, FieldValue: context.FieldValue});
  for (const [name, next] of [['removeNeighbor', 'setUserRole'], ['getAccessRequestStatus', 'requestPasswordResetCode']]) {
    const start = source.indexOf(`exports.${name} =`);
    const end = source.indexOf(`exports.${next} =`, start);
    vm.runInNewContext(source.slice(start, end), context);
  }
  return {data, batchSizes, context, authDeletes: () => authDeletes};
}

test('la baja conserva historial, respeta UID y no cambia solicitudes nuevas', async () => {
  const f = fixture({members: [['u', {role: 'vecino', dni: '00000000'}]], requests: [
    ['linked', {approvedUserId: 'u', status: 'aprobado', dni: '00000001'}],
    ['legacy', {status: 'aprobado', dni: '00000000'}],
    ['other', {approvedUserId: 'other', status: 'aprobado', dni: '00000000'}],
    ['pending', {status: 'pendiente', dni: '00000000'}],
  ]});
  await f.context.exports.removeNeighbor({auth: {uid: 'admin'}, data: {userId: 'u'}});
  assert.equal(f.data.users.has('u'), false);
  assert.equal(f.data.accessRequests.get('linked').status, 'retirado');
  assert.equal(f.data.accessRequests.get('legacy').removedBy, 'admin');
  assert.equal(f.data.accessRequests.get('other').status, 'aprobado');
  assert.equal(f.data.accessRequests.get('pending').status, 'pendiente');
});

test('más de 500 solicitudes se procesan en lotes', async () => {
  const f = fixture({members: [['u', {role: 'vecino'}]], requests:
    Array.from({length: 801}, (_, i) => [`r${i}`, {approvedUserId: 'u', status: 'aprobado'}])});
  await f.context.exports.removeNeighbor({auth: {uid: 'admin'}, data: {userId: 'u'}});
  assert.deepEqual(f.batchSizes, [400, 400, 1]);
});

test('un fallo conserva el perfil y una cuenta ya borrada permite reintentar', async () => {
  const options = {members: [['u', {role: 'vecino'}]], requests: [['r', {approvedUserId: 'u', status: 'aprobado'}]]};
  const failed = fixture({...options, failBatch: true});
  await assert.rejects(failed.context.exports.removeNeighbor({auth: {uid: 'admin'}, data: {userId: 'u'}}), {code: 'internal'});
  assert.equal(failed.data.users.has('u'), true);
  const retry = fixture({...options, missingAuth: true});
  await retry.context.exports.removeNeighbor({auth: {uid: 'admin'}, data: {userId: 'u'}});
  assert.equal(retry.data.users.has('u'), false);
});

test('una baja anterior no bloquea el reingreso ni modifica el historial', async () => {
  const f = fixture({requests: [['r', {approvedUserId: 'deleted', status: 'aprobado', dni: '00000000'}]]});
  const result = await f.context.exports.getAccessRequestStatus({data: {dni: '00000000'}});
  assert.equal(result.request.status, 'retirado');
  assert.equal(f.data.accessRequests.get('r').status, 'aprobado');
});

test('un miembro vigente mantiene su aprobación y un vecino no puede retirar miembros', async () => {
  const f = fixture({members: [['u', {role: 'vecino'}]], requests: [['r', {approvedUserId: 'u', status: 'aprobado', dni: '00000000'}]]});
  assert.equal((await f.context.exports.getAccessRequestStatus({data: {dni: '00000000'}})).request.status, 'aprobado');
  await assert.rejects(f.context.exports.removeNeighbor({auth: {uid: 'neighbor'}, data: {userId: 'u'}}), {code: 'permission-denied'});
  assert.equal(f.authDeletes(), 0);
});

test('consultar por DNI no devuelve el correo completo ni cambia el dato almacenado', async () => {
  for (const status of ['pendiente', 'rechazado', 'aprobado', 'retirado']) {
    const f = fixture({members: [['u', {role: 'vecino'}]], requests: [['r', {
      approvedUserId: 'u', status, dni: '00000000', email: 'holaadios@example.com',
    }]]});
    const result = await f.context.exports.getAccessRequestStatus({data: {dni: '00000000'}});
    assert.equal(result.request.email, 'ho****@***.com');
    assert.equal(f.data.accessRequests.get('r').email, 'holaadios@example.com');
    assert.ok(!JSON.stringify(result).includes('holaadios@example.com'));
  }
});

test('la baja conserva el DNI corregido y datos actuales sin sobrescribir la solicitud original', async () => {
  const f = fixture({members: [['u', {role: 'vecino', dni: '00000002', nombre: 'Updated Demo',
    email: 'updated@example.com', phone: '000000002', address: 'Current demo address',
    timeLivingHere: '5 a 10 años', reason: 'Corrected demo reason'}]], requests: [['r', {
    approvedUserId: 'u', status: 'aprobado', dni: '00000001', name: 'Original Demo',
    email: 'original@example.com', reason: 'Original reason',
  }]]});
  await f.context.exports.removeNeighbor({auth: {uid: 'admin'}, data: {userId: 'u'}});
  assert.equal(f.data.users.has('u'), false);
  const stored = f.data.accessRequests.get('r');
  assert.equal(stored.dni, '00000001');
  assert.equal(stored.reason, 'Original reason');
  assert.equal(stored.currentProfile.reason, 'Corrected demo reason');
  assert.equal((await f.context.exports.getAccessRequestStatus({data: {dni: '00000001'}})).request, null);
  const current = (await f.context.exports.getAccessRequestStatus({data: {dni: '00000002'}})).request;
  assert.equal(current.status, 'retirado');
  assert.equal(current.name, 'Updated Demo');
  assert.equal(current.email, 'up****@***.com');
});
