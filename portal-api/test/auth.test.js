import test from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../src/app.js';
import { issueAccessToken } from '../src/services/auth.service.js';

process.env.JWT_SECRET ??= 'test-only-jwt-secret-with-at-least-32-characters';

const validClaims = {
  userId: 'user-admin-alpha',
  organizationId: 'org-demo-alpha',
  scopes: ['organization.read', 'access.read']
};

function request(app, authorization) {
  return app.handle({
    method: 'GET',
    url: '/v1/me',
    headers: authorization ? { authorization } : {}
  });
}

test('middleware bloqueia requisição sem token', async () => {
  const result = await request(createApp());
  assert.equal(result.status, 401);
  assert.deepEqual(result.body, { error: 'AUTH_REQUIRED' });
});

test('middleware aceita token válido e disponibiliza a identidade', async () => {
  const token = issueAccessToken(validClaims);
  const result = await request(createApp(), `Bearer ${token}`);
  assert.equal(result.status, 200);
  assert.deepEqual(result.body, {
    id: validClaims.userId,
    status: 'active',
    storageMode: 'memory-test-only'
  });
});

test('middleware rejeita token expirado com resposta padronizada de renovação', async () => {
  const token = issueAccessToken(validClaims, { expiresIn: -1 });
  const result = await request(createApp(), `Bearer ${token}`);
  assert.equal(result.status, 401);
  assert.deepEqual(result.body, {
    error: 'TOKEN_EXPIRED',
    code: 'TOKEN_EXPIRED',
    renewalRequired: true
  });
});

test('middleware rejeita token corrompido', async () => {
  const result = await request(createApp(), 'Bearer not.a.jwt');
  assert.deepEqual(result, { status: 401, body: { error: 'INVALID_TOKEN' } });
});
