import { AsyncLocalStorage } from 'node:async_hooks';
import { createHash } from 'node:crypto';
import { AuthorizationError } from './authorization.js';

// Only server-owned table and column names can enter SQL. Values are parameterized.
const definitions = {
  activationTokens: ['activation_tokens', 'id invitationId userId expiresAt usedAt'],
  users: ['users', 'id externalSubject status email passwordHash createdAt updatedAt'],
  organizations: ['organizations', 'id name type status createdAt updatedAt'],
  memberships: ['memberships', 'id userId organizationId role status validUntil scopes'],
  subjects: ['child_subjects', 'id familySpaceId ownerUserId displayName status createdAt'],
  consents: ['consents', 'id subjectId organizationId grantedByUserId recipientUserId purpose scopes noticeVersion status validUntil createdAt revokedAt'],
  invitations: ['invitations', 'id organizationId inviteeUserId subjectId consentId purpose scopes role status expiresAt'],
  relationships: ['care_relationships', 'id userId subjectId organizationId role status validUntil'],
  grants: ['access_grants', 'id userId subjectId organizationId consentId purpose scopes status validUntil'],
  benefits: ['benefit_entitlements', 'id organizationId status validUntil'],
  auditEvents: ['audit_events', 'id userId organizationId action result code requestId occurredAt apiVersion'],
};
const column = (name) => name.replace(/[A-Z]/g, (c) => `_${c.toLowerCase()}`);
const canonical = (value) => Array.isArray(value) ? value.map(canonical)
  : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonical(value[key])])) : value;

export function attachRepository(store) {
  const context = new AsyncLocalStorage();
  const locks = new Map();
  store.withLock = async (key, operation) => {
    if (store.pool) {
      await store.database.query('select pg_advisory_xact_lock(hashtextextended($1,0))', [key]);
      return operation();
    }
    const previous = locks.get(key) ?? Promise.resolve();
    const current = previous.catch(() => {}).then(operation);
    locks.set(key, current);
    try { return await current; } finally { if (locks.get(key) === current) locks.delete(key); }
  };
  store.database = { query: (...args) => (context.getStore() ?? store.pool).query(...args) };
  store.transaction = async (callback) => {
    if (!store.pool || context.getStore()) return callback();
    const connection = await store.pool.connect();
    try {
      await connection.query('begin');
      const result = await context.run(connection, callback);
      await connection.query('commit');
      return result;
    } catch (error) {
      await connection.query('rollback');
      throw error;
    } finally { connection.release(); }
  };
  function schema(kind, fields) {
    const definition = definitions[kind];
    if (!definition) throw new TypeError('Unknown record type');
    const allowed = definition[1].split(' ');
    if (fields.some((field) => !allowed.includes(field))) throw new TypeError('Unknown record field');
    return { table: definition[0], allowed };
  }
  store.listRecords = async (kind, filter = {}) => {
    const keys = Object.keys(filter);
    const { table, allowed } = schema(kind, keys);
    if (!store.pool) return store[kind].filter((row) => keys.every((key) => row[key] === filter[key]));
    const where = keys.length ? ` where ${keys.map((key, i) => `${column(key)} = $${i + 1}`).join(' and ')}` : '';
    const result = await store.database.query(`select ${allowed.map((field) => `${column(field)} as "${field}"`).join(',')} from ${table}${where}`, keys.map((key) => filter[key]));
    return result.rows.map((row) => Object.fromEntries(Object.entries(row).map(([key, value]) => [key, value instanceof Date ? value.toISOString() : value])));
  };
  store.findRecord = async (kind, filter) => (await store.listRecords(kind, filter))[0];
  store.saveRecord = async (kind, record) => {
    const keys = Object.keys(record);
    const { table } = schema(kind, keys);
    if (!store.pool) {
      const index = store[kind].findIndex((row) => row.id === record.id);
      if (index < 0) store[kind].push(record); else store[kind][index] = record;
      return record;
    }
    await store.database.query(`insert into ${table} (${keys.map(column).join(',')}) values (${keys.map((_, i) => `$${i + 1}`).join(',')}) on conflict (id) do update set ${keys.filter((key) => key !== 'id').map((key) => `${column(key)} = excluded.${column(key)}`).join(',')}`, keys.map((key) => record[key]));
    return record;
  };
  store.idempotent = async (identity, body, handler) => {
    if (!identity.requestId) return handler();
    if (typeof identity.requestId !== 'string' || identity.requestId.length > 200) throw new AuthorizationError('INVALID_REQUEST_ID', 400);
    const key = createHash('sha256').update(JSON.stringify(identity)).digest('hex');
    const hash = createHash('sha256').update(JSON.stringify(canonical(body))).digest('hex');
    if (store.pool) return store.transaction(async () => {
      // The lock and the write/result share the same DB transaction, including across processes.
      await store.database.query('select pg_advisory_xact_lock(hashtextextended($1, 0))', [key]);
      const existing = await store.database.query('select payload_hash, result from idempotency_records where id = $1', [key]);
      if (existing.rows[0]) {
        if (existing.rows[0].payload_hash !== hash) throw new AuthorizationError('IDEMPOTENCY_CONFLICT', 409);
        return existing.rows[0].result;
      }
      const result = await handler();
      await store.database.query('insert into idempotency_records (id, payload_hash, result) values ($1,$2,$3::jsonb)', [key, hash, JSON.stringify(result)]);
      return result;
    });
    const existing = store.idempotency.get(key);
    if (existing) {
      if (existing.hash !== hash) throw new AuthorizationError('IDEMPOTENCY_CONFLICT', 409);
      return existing.promise;
    }
    const promise = Promise.resolve().then(handler);
    store.idempotency.set(key, { hash, promise });
    try { return await promise; } catch (error) { store.idempotency.delete(key); throw error; }
  };
}
