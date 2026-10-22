const {createProfileIdentity} = require('../../profile_identity');

class HttpsError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}

function fixture({members = [], requests = [], keys = [], authError = null, failWrite = false} = {}) {
  const data = {users: new Map(members), accessRequests: new Map(requests), memberDniKeys: new Map(keys), memberEmailKeys: new Map()};
  const authWrites = [];
  let transactionTail = Promise.resolve();
  const snapshot = (collection, id) => {
    const value = data[collection].get(id);
    return {id, ref: reference(collection, id), exists: value !== undefined,
      data: () => value === undefined ? undefined : {...value}};
  };
  function reference(collection, id) {
    return {id, collection, get: async () => snapshot(collection, id),
      delete: async () => data[collection].delete(id)};
  }
  function query(collection, filters = []) {
    return {doc: (id) => reference(collection, id),
      where: (field, operator, value) => {
        if (operator !== '==') throw new Error('Unsupported test operator');
        return query(collection, [...filters, [field, value]]);
      },
      get: async () => {
        const docs = [...data[collection]].filter(([, row]) =>
          filters.every(([field, value]) => row[field] === value)).map(([id]) => snapshot(collection, id));
        return {docs, empty: docs.length === 0};
      }};
  }
  const db = {
    collection: (name) => query(name),
    runTransaction: (callback) => {
      const run = transactionTail.then(async () => {
        const operations = [];
        const transaction = {
          get: async (target) => {
            if (operations.length) throw new Error('Firestore reads must precede writes');
            return target.get();
          },
          set: (ref, value) => operations.push(['set', ref, value]),
          update: (ref, value) => operations.push(['update', ref, value]),
          delete: (ref) => operations.push(['delete', ref]),
        };
        const result = await callback(transaction);
        if (failWrite && operations.length) throw new Error('Simulated Firestore failure');
        for (const [operation, ref, value] of operations) {
          if (operation === 'delete') data[ref.collection].delete(ref.id);
          else data[ref.collection].set(ref.id, operation === 'update' ?
            {...data[ref.collection].get(ref.id), ...value} : {...value});
        }
        return result;
      });
      transactionTail = run.catch(() => {});
      return run;
    },
  };
  const auth = {getUserByEmail: async (email) => {
    const match = [...data.users].find(([, profile]) => String(profile.email || '').trim().toLowerCase() === email);
    if (match) return {uid: match[0]};
    throw Object.assign(new Error('Fictional account absent'), {code: 'auth/user-not-found'});
  }, updateUser: async (uid, values) => {
    if (authError) throw Object.assign(new Error('Simulated Auth failure'), {code: authError});
    authWrites.push({uid, ...values});
  }};
  const identity = createProfileIdentity({firestore: db, auth, HttpsError,
    FieldValue: {serverTimestamp: () => 'server-time'}});
  return {identity, data, db, auth, authWrites, HttpsError};
}

module.exports = {fixture, HttpsError};
