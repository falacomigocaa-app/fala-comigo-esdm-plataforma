import test from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../src/app.js';
import { issueAccessToken, verifyAccessToken } from '../src/services/auth.service.js';

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

test('refresh emite novos tokens e revoga o token anterior', async () => {
  const now = new Date('2026-10-05T12:00:00.000Z');
  const app = createApp({ now: () => now });
  const refreshToken = await app.store.createRefreshToken(validClaims, now);
  const result = await app.handle({
    method: 'POST',
    url: '/v1/auth/refresh',
    body: { refreshToken }
  });

  assert.equal(result.status, 200);
  assert.equal(typeof result.body.accessToken, 'string');
  assert.equal(typeof result.body.refreshToken, 'string');
  assert.notEqual(result.body.refreshToken, refreshToken);
  assert.equal(result.body.expiresIn, 900);
  const claims = verifyAccessToken(result.body.accessToken);
  assert.equal(claims.userId, validClaims.userId);
  assert.deepEqual(claims.scopes, validClaims.scopes);

  const replay = await app.handle({
    method: 'POST',
    url: '/v1/auth/refresh',
    body: { refreshToken }
  });
  assert.deepEqual(replay, { status: 401, body: { error: 'REFRESH_TOKEN_INVALID' } });
});

test('refresh rejeita token expirado sem revelar a sessão', async () => {
  const issuedAt = new Date('2026-10-01T12:00:00.000Z');
  const now = new Date('2026-10-10T12:00:00.000Z');
  const app = createApp({ now: () => now });
  const refreshToken = await app.store.createRefreshToken(validClaims, issuedAt);
  const result = await app.handle({
    method: 'POST',
    url: '/v1/auth/refresh',
    body: { refreshToken }
  });
  assert.deepEqual(result, { status: 401, body: { error: 'REFRESH_TOKEN_INVALID' } });
});
