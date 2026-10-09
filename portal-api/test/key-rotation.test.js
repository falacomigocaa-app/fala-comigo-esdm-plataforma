import test from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../src/app.js';
import { issueAccessToken } from '../src/services/auth.service.js';
import { roleScopes } from '../src/store.js';

process.env.JWT_SECRET ??= 'test-only-jwt-secret-with-at-least-32-characters';
const previousMasterKey = process.env.MASTER_CRYPTO_KEY;
process.env.MASTER_CRYPTO_KEY = Buffer.alloc(32, 31).toString('base64');

test.after(() => {
  if (previousMasterKey === undefined) delete process.env.MASTER_CRYPTO_KEY;
  else process.env.MASTER_CRYPTO_KEY = previousMasterKey;
});

function request(app, method, url, userId, body = null) {
  const membership = app.store.memberships.find((item) => item.userId === userId && item.status === 'active');
  const token = issueAccessToken({ userId, organizationId: membership.organizationId, scopes: roleScopes[membership.role] ?? [] });
  return app.handle({ method, url, headers: { authorization: `Bearer ${token}` }, body });
}

test('login distribui chave com versão e rotação preserva a versão anterior', async () => {
  const app = createApp();
  if (app.store.pool) {
    await app.store.pool.query("delete from organization_key_versions where organization_id = 'org-demo-alpha'");
    await app.store.pool.query("delete from organization_keys where organization_id = 'org-demo-alpha'");
  }
  const first = await app.store.provisionOrganizationKey({ organizationId: 'org-demo-alpha', createdByUserId: 'user-admin-alpha' });
  assert.equal(first.keyVersion, 1);

  const login = await app.handle({
    method: 'POST', url: '/v1/auth/login',
    body: { email: 'admin@fala-comigo.test', password: 'DemoPassword-2026' }
  });
  assert.equal(login.status, 200);
  assert.equal(login.body.keyVersion, 1);

  const rotated = await request(app, 'POST', '/v1/organizations/org-demo-alpha/keys/rotate', 'user-admin-alpha');
  assert.equal(rotated.status, 201);
  assert.equal(rotated.body.keyVersion, 2);
  assert.notEqual(rotated.body.organizationKey, first.organizationKey);

  const old = await request(app, 'GET', '/v1/organizations/org-demo-alpha/keys?version=1', 'user-admin-alpha');
  assert.equal(old.status, 200);
  assert.equal(old.body.keyVersion, 1);
  assert.equal(old.body.organizationKey, first.organizationKey);
});

test('profissional sem escopo de rotação não pode trocar a chave', async () => {
  const app = createApp();
  await app.store.provisionOrganizationKey({ organizationId: 'org-demo-alpha', createdByUserId: 'user-admin-alpha' });
  const result = await request(app, 'POST', '/v1/organizations/org-demo-alpha/keys/rotate', 'user-professional-alpha');
  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'SCOPE_DENIED');
});

test('login de profissional sem leitura de chave não recebe material E2EE', async () => {
  const app = createApp();
  await app.store.provisionOrganizationKey({ organizationId: 'org-demo-alpha', createdByUserId: 'user-admin-alpha' });
  const result = await app.handle({
    method: 'POST',
    url: '/v1/auth/login',
    body: { email: 'profissional@fala-comigo.test', password: 'DemoPassword-2026' }
  });
  assert.equal(result.status, 200);
  assert.equal('organizationKey' in result.body, false);
  assert.equal('keyVersion' in result.body, false);
});
