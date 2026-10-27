const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {maskPublicEmail} = require('../privacy');

test('el correo público conserva el dominio y protege direcciones cortas', () => {
  const cases = JSON.parse(fs.readFileSync(path.join(__dirname, '../../test/fixtures/public_email_masks.json'), 'utf8'));
  for (const [input, expected] of cases) {
    assert.equal(maskPublicEmail(input), expected);
    assert.equal(maskPublicEmail(expected), expected, 'No debe alterar una respuesta ya oculta');
  }
});

test('nunca revela más de la mitad de una parte local original ni devuelve el correo completo', () => {
  for (let length = 1; length <= 64; length++) {
    const local = 'abcdefghijklmnopqrstuvwxyz'.repeat(3).slice(0, length);
    const original = `${local}@example.com`;
    const masked = maskPublicEmail(original);
    const visible = masked.split('@')[0].replace(/\*/g, '').length;
    assert.notEqual(masked, original);
    assert.ok(visible <= Math.floor(length / 2));
    assert.ok(visible <= 3);
    assert.equal(maskPublicEmail(masked), masked);
  }
});

test('el resumen público no consulta ni devuelve ninguna reunión', async () => {
  const source = fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8');
  const queried = [];
  const context = {
    exports: {}, region: 'local', onCall: (_, callback) => callback,
    getFirestore: () => ({collection: (name) => {
      queried.push(name);
      assert.notEqual(name, 'events');
      const query = {
        where: () => query, count: () => query,
        get: async () => ({data: () => ({count: name === 'users' ? 3 : 2})}),
      };
      return query;
    }}),
  };
  const start = source.indexOf('exports.getPublicCommunitySummary =');
  const end = source.indexOf('async function requireAdmin', start);
  vm.runInNewContext(source.slice(start, end), context);
  const result = await context.exports.getPublicCommunitySummary();
  assert.deepEqual(JSON.parse(JSON.stringify(result)), {activeMembers: 3, projects: 2});
  assert.deepEqual(queried, ['users', 'projects']);
});
