// Execute na raiz do repositório: node --test <caminho>/regressoes-api.test.mjs
// Usa somente dados sintéticos em memória. As expectativas descrevem o comportamento seguro.
import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

const root = resolve(new URL('..', import.meta.url).pathname, '..');
const moduleAt = (file) => import(pathToFileURL(resolve(root, file)).href);
const { createApp } = await moduleAt('portal-api/src/app.js');
const { createStore, roleScopes } = await moduleAt('portal-api/src/store.js');
const { issueAccessToken, hashRefreshToken } = await moduleAt('portal-api/src/services/auth.service.js');
process.env.JWT_SECRET = randomBytes(48).toString('hex');
delete process.env.MASTER_CRYPTO_KEY;

function request(app, method, url, userId, body, id) {
  const membership = app.store.memberships.find((item) => item.userId === userId);
  const token = issueAccessToken({ userId, organizationId: membership.organizationId, scopes: roleScopes[membership.role] });
  return app.handle({ method, url, body, headers: { authorization: `Bearer ${token}`, ...(id ? { 'x-request-id': id } : {}) } });
}

test('A01: consentimento vencido pelo relógio real deve bloquear leitura', async () => {
  const store = createStore({ pool: null });
  store.consents.find((x) => x.id === 'consent-demo-clinic').validUntil = '2026-10-01T00:00:00Z';
  assert.ok(new Date() > new Date('2026-10-01'), 'Este cenário exige execução posterior a 01/10/2026');
  const result = await request(createApp({ store }), 'GET', '/v1/subjects/subject-demo-child/esdm-goals', 'user-professional-alpha');
  assert.equal(result.status, 403, 'consentimento expirado foi aceito');
});

test('A01b: refresh token vencido pelo relógio real deve ser recusado', async () => {
  const store = createStore({ pool: null });
  const token = await store.createRefreshToken({ userId: 'user-admin-alpha', organizationId: 'org-demo-alpha', scopes: roleScopes.owner }, new Date('2026-09-25T12:00:00Z'));
  assert.ok(new Date(store.refreshTokens.get(hashRefreshToken(token)).expiresAt) < new Date());
  const result = await createApp({ store }).handle({ method: 'POST', url: '/v1/auth/refresh', body: { refreshToken: token } });
  assert.equal(result.status, 401, 'refresh vencido foi renovado');
});

test('A02: membership revogada deve bloquear acesso clínico mesmo com grant ativo', async () => {
  const store = createStore({ pool: null });
  store.memberships.find((x) => x.userId === 'user-professional-alpha').status = 'revoked';
  const result = await request(createApp({ store, now: () => new Date() }), 'GET', '/v1/subjects/subject-demo-child/esdm-goals', 'user-professional-alpha');
  assert.equal(result.status, 403, 'rota clínica ignorou revogação de membership');
});

test('A03: login deve respeitar o mesmo escopo de leitura de chave que GET /keys', async () => {
  process.env.MASTER_CRYPTO_KEY = randomBytes(32).toString('base64');
  try {
    const store = createStore({ pool: null });
    await store.provisionOrganizationKey({ organizationId: 'org-demo-alpha', createdByUserId: 'user-admin-alpha' });
    const app = createApp({ store, now: () => new Date() });
    const denied = await request(app, 'GET', '/v1/organizations/org-demo-alpha/keys', 'user-professional-alpha');
    assert.equal(denied.status, 403);
    const login = await app.handle({ method: 'POST', url: '/v1/auth/login', body: { email: 'profissional@fala-comigo.test', password: 'DemoPassword-2026' } });
    assert.equal(login.status, 200);
    assert.equal(typeof login.body.organizationKey, 'undefined', 'login expôs chave negada pelo endpoint protegido');
  } finally {
    delete process.env.MASTER_CRYPTO_KEY;
  }
});

test('A04: request-id compartilhado entre organizações não deve devolver dados de outro paciente', async () => {
  const store = createStore({ pool: null });
  store.subjects.push({ id: 'subject-audit-beta', ownerUserId: 'user-admin-beta', status: 'active' });
  const app = createApp({ store, now: () => new Date() });
  const body = { codigoTecnicoDenver: 'CE_N1_I5' };
  const first = await request(app, 'POST', '/v1/subjects/subject-demo-child/esdm-goals', 'user-admin-alpha', body, 'audit-shared-request');
  assert.equal(first.status, 201);
  const second = await request(app, 'POST', '/v1/subjects/subject-audit-beta/esdm-goals', 'user-admin-beta', body, 'audit-shared-request');
  assert.equal(second.status, 201);
  assert.equal(second.body.goal.subjectId, 'subject-audit-beta', 'retornou meta de outro paciente/organização');
});

test('A04b: duas gravações concorrentes com o mesmo request-id devem criar uma única meta', async () => {
  const store = createStore({ pool: null });
  const app = createApp({ store, now: () => new Date() });
  const send = () => request(app, 'POST', '/v1/subjects/subject-demo-child/esdm-goals', 'user-admin-alpha', { codigoTecnicoDenver: 'CE_N1_I5' }, 'audit-concurrent-request');
  const results = await Promise.all([send(), send()]);
  assert.ok(results.every((r) => r.status === 201));
  assert.equal(store.goals.length, 1, 'retry concorrente duplicou a gravação');
});

