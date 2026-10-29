// Fictional records and function doubles only: no real Firebase connection.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {fixture, HttpsError} = require('./helpers/identity_fixture.cjs');

function callable(identity) {
  const source = fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8');
  const start = source.indexOf('exports.getAccessRequestStatus =');
  const end = source.indexOf('\nexports.', start + 8);
  const context = {exports: {}, region: 'local', HttpsError,
    onCall: (_, handler) => handler, profileIdentity: () => identity};
  vm.runInNewContext(source.slice(start, end), context);
  return context.exports.getAccessRequestStatus;
}

for (const dni of [undefined, null, 12345678, ['12345678'], {}, '', '1234567',
  '123456789', '1234 678', '１２３４５６７８', 'abcdefgh', '0000000\n1']) {
  test(`DNI inválido ${JSON.stringify(dni)} se rechaza antes de consultar`, async () => {
    let calls = 0;
    const lookup = callable({findRequestStatus: async () => calls++});
    await assert.rejects(lookup({data: {dni}}), {code: 'invalid-argument'});
    assert.equal(calls, 0);
  });
}

test('consulta sin sesión conserva ceros iniciales y acepta espacios exteriores', async () => {
  const seen = [];
  const lookup = callable({findRequestStatus: async dni => {
    seen.push(dni); return {request: null};
  }});
  assert.equal((await lookup({data: {dni: ' 00000001 '}})).request, null);
  assert.deepEqual(seen, ['00000001']);
});

for (const status of ['pendiente', 'rechazado', 'aprobado', 'retirado']) {
  test(`respuesta ${status} devuelve solo estado, fecha y correo enmascarado, nunca el motivo`, async () => {
    const created = {toDate: () => new Date('2026-10-04T12:00:00Z')};
    const original = {name: 'Private Fictional Applicant', dni: '00000001',
      email: 'fabrizio@example.com', status, phone: '000000001', address: 'Private Fictional Place',
      reason: 'Private Fictional Reason', rejectionReason: 'El documento adjunto no es legible.',
      identityDocumentPath: 'private/document', identityDocumentUrl: 'https://example.invalid/private',
      createdAt: created, approvedUserId: 'member-a'};
    const f = fixture({requests: [['request-a', original]],
      members: status === 'aprobado' ? [['member-a', {role: 'vecino', approvalStatus: 'aprobado',
        nombre: 'Current Private Name', dni: '00000001', email: 'updated@example.com'}]] : []});
    const lookup = callable(f.identity);
    const result = await lookup({data: {dni: '00000001', includeName: true,
      fields: ['name', 'rejectionReason', 'identityDocumentUrl'],
      includeRejectionReason: true, email: 'attacker@example.com'}});
    assert.deepEqual(Object.keys(result), ['request']);
    assert.deepEqual(Object.keys(result.request).sort(), ['createdAt', 'email', 'status']);
    assert.equal(result.request.status, status);
    assert.equal(result.request.createdAt, '2026-10-04T12:00:00.000Z');
    assert.equal(result.request.email, status === 'aprobado' ? 'up****d@example.com' : 'fa*****o@example.com');
    assert.deepEqual(f.data.accessRequests.get('request-a'), original);
    const output = JSON.stringify(result);
    for (const privateValue of [original.name, original.email, original.address,
      original.reason, original.identityDocumentUrl, original.phone, original.rejectionReason]) {
      assert.equal(output.includes(privateValue), false);
    }
    assert.equal(f.authWrites.length, 0);
  });
}

for (const reason of [undefined, null, '', '   ', 123, {}, ['motivo']]) {
  test(`rechazo histórico con motivo inválido ${JSON.stringify(reason)} mantiene una respuesta mínima`, async () => {
    const f = fixture({requests: [['request-a', {dni: '00000001', status: 'rechazado',
      email: 'applicant@example.com', rejectionReason: reason}]]});
    const result = await callable(f.identity)({data: {dni: '00000001'}});
    assert.deepEqual(Object.keys(result.request).sort(), ['createdAt', 'email', 'status']);
    assert.equal(result.request.status, 'rechazado');
  });
}

test('un motivo extenso permanece interno y no se modifica al consultar públicamente', async () => {
  const f = fixture({requests: [['request-a', {dni: '00000001', status: 'rechazado',
    email: 'applicant@example.com', rejectionReason: '  ' + 'x'.repeat(1005) + '  '}]]});
  const result = await callable(f.identity)({data: {dni: '00000001'}});
  assert.deepEqual(Object.keys(result.request).sort(), ['createdAt', 'email', 'status']);
  assert.equal(Object.hasOwn(result.request, 'rejectionReason'), false);
  assert.equal(f.data.accessRequests.get('request-a').rejectionReason.length, 1009);
});

test('un DNI desconocido no devuelve información ni modifica registros', async () => {
  const f = fixture();
  assert.deepEqual(await callable(f.identity)({data: {dni: '00000001'}}), {request: null});
  assert.equal(f.data.accessRequests.size, 0);
  assert.equal(f.data.users.size, 0);
});
