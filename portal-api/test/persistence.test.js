// Execute somente em banco descartável com migrations e ci-seed.sql aplicados.
// AUDIT_DATABASE_URL deve apontar explicitamente para esse banco local.
import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes, createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
const root = resolve(new URL('..', import.meta.url).pathname, '..');
const moduleAt = (file) => import(pathToFileURL(resolve(root, file)).href);
const databaseUrl = process.env.PGTEST_URL;
const pgTest = (name, fn) => test(name, { skip: !databaseUrl }, fn);
const dbUrl = new URL(databaseUrl || 'postgres://localhost/unused');
assert.ok(['localhost', '127.0.0.1', '[::1]'].includes(dbUrl.hostname), 'Somente banco local');
if (databaseUrl) process.env.DATABASE_URL = databaseUrl;
process.env.JWT_SECRET = randomBytes(48).toString('hex');
delete process.env.MASTER_CRYPTO_KEY;
const { createStore, roleScopes } = await moduleAt('portal-api/src/store.js');
const { createApp } = await moduleAt('portal-api/src/app.js');
const { issueAccessToken } = await moduleAt('portal-api/src/services/auth.service.js');
const headers = (id, role) => ({ authorization: `Bearer ${issueAccessToken({ userId: id, organizationId: 'org-demo-alpha', scopes: roleScopes[role] })}` });

pgTest('A05: API com PostgreSQL deve manter revogação após recriar aplicação', async () => {
  const first = createStore();
  let second;
  const originalGrant = await first.findRecord('grants', { id: 'grant-demo-clinic' });
  const originalConsent = await first.findRecord('consents', { id: originalGrant.consentId });
  try {
    await first.saveRecord('grants', { ...originalGrant, status: 'active', validUntil: '2099-01-01T00:00:00.000Z' });
    await first.saveRecord('consents', { ...originalConsent, status: 'active', revokedAt: null, validUntil: '2099-01-01T00:00:00.000Z' });
    const app = createApp({ store: first, now: () => new Date() });
    assert.equal(first.storageMode, 'postgres');
    const before = await app.handle({ method: 'GET', url: '/v1/subjects/subject-demo-child/esdm-goals', headers: headers('user-professional-alpha', 'professional') });
    assert.equal(before.status, 200, 'pré-condição: acesso ativo antes de revogar');
    const revoked = await app.handle({ method: 'POST', url: '/v1/subjects/subject-demo-child/grants/grant-demo-clinic/revoke', headers: headers('user-admin-alpha', 'owner') });
    assert.equal(revoked.status, 200);
    const denied = await app.handle({ method: 'GET', url: '/v1/subjects/subject-demo-child/esdm-goals', headers: headers('user-professional-alpha', 'professional') });
    assert.equal(denied.status, 403);
    second = createStore();
    const afterRestart = await createApp({ store: second, now: () => new Date() }).handle({ method: 'GET', url: '/v1/subjects/subject-demo-child/esdm-goals', headers: headers('user-professional-alpha', 'professional') });
    assert.equal(afterRestart.status, 403, 'banco conectado, mas restart reativou acesso clínico');
  } finally {
    await first.saveRecord('grants', originalGrant);
    await first.saveRecord('consents', originalConsent);
    await first.pool.end();
    await second?.pool.end();
  }
});

pgTest('A05b: usuário cadastrado no PostgreSQL deve usar o token emitido no login', async () => {
  const store = createStore();
  const userId = `audit-user-${randomBytes(6).toString('hex')}`;
  const membershipId = `membership-${userId}`;
  try {
    await store.pool.query(`insert into users (id, external_subject, status, email, password_hash)
      select $1, $1, 'active', $2, password_hash from users where id = 'user-admin-alpha'`, [userId, `${userId}@fala-comigo.test`]);
    await store.pool.query(`insert into memberships (id, user_id, organization_id, role, status, valid_until)
      values ($1, $2, 'org-demo-alpha', 'professional', 'active', '2099-01-01')`, [membershipId, userId]);
    const app = createApp({ store, now: () => new Date() });
    const login = await app.handle({ method: 'POST', url: '/v1/auth/login', body: { email: `${userId}@fala-comigo.test`, password: 'DemoPassword-2026' } });
    assert.equal(login.status, 200, 'pré-condição: login real via PostgreSQL');
    const me = await app.handle({ method: 'GET', url: '/v1/me', headers: { authorization: `Bearer ${login.body.accessToken}` } });
    assert.equal(me.status, 200, 'token legítimo de usuário PostgreSQL foi recusado');
  } finally {
    await store.pool.query('delete from refresh_tokens where user_id = $1', [userId]);
    await store.pool.query('delete from memberships where id = $1', [membershipId]);
    await store.pool.query('delete from users where id = $1', [userId]);
    await store.pool.end();
  }
});

pgTest('idempotência PostgreSQL resiste à concorrência e ao restart e rejeita payload diferente', async () => {
  const store = createStore();
  const restarted = createStore();
  const requestId = `postgres-race-${randomBytes(12).toString('hex')}`;
  const url = '/v1/subjects/subject-demo-child/esdm-goals';
  const identity = { requestId, userId: 'user-admin-alpha', organizationId: 'org-demo-alpha', method: 'POST', url };
  const cacheId = createHash('sha256').update(JSON.stringify(identity)).digest('hex');
  const request = { method: 'POST', url, headers: { ...headers('user-admin-alpha', 'owner'), 'x-request-id': requestId }, body: { codigoTecnicoDenver: 'CE_N1_I5', status: 'Em Progresso' } };
  let goalId;
  try {
    const app = createApp({ store });
    const [first, second] = await Promise.all([app.handle(request), app.handle(request)]);
    assert.equal(first.status, 201);
    goalId = first.body.goal.id;
    assert.equal(second.status, 201);
    assert.equal(second.body.goal.id, goalId);
    const otherApp = createApp({ store: restarted });
    const repeat = await otherApp.handle(request);
    assert.equal(repeat.body.goal.id, goalId);
    const conflict = await otherApp.handle({ ...request, body: { ...request.body, status: 'Adquirido' } });
    assert.equal(conflict.status, 409);
    const rows = await store.pool.query('select id from esdm_goals where id = $1', [goalId]);
    assert.equal(rows.rowCount, 1);
  } finally {
    await store.pool.query('delete from idempotency_records where id = $1', [cacheId]);
    if (goalId) await store.pool.query('delete from esdm_goals where id = $1', [goalId]);
    await store.pool.query('delete from audit_events where request_id = $1', [requestId]);
    await store.pool.end();
    await restarted.pool.end();
  }
});
