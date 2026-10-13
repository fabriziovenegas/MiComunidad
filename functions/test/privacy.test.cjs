const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {maskPublicEmail} = require('../privacy');

test('el correo público oculta dominio, longitud y direcciones cortas', () => {
  for (const [input, expected] of [
    ['holaadios@example.com', 'ho****@***.com'],
    ['ab@example.com', 'a****@***.com'],
    ['a@example.com', '****@***.com'],
    ['  hello@example.co.uk  ', 'he****@***.uk'],
    ['ho****@***.com', 'ho****@***.com'],
    ['a****@***.com', 'a****@***.com'],
    [null, ''], ['', ''], ['invalid', ''], ['a@@example.com', ''],
  ]) assert.equal(maskPublicEmail(input), expected);
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
