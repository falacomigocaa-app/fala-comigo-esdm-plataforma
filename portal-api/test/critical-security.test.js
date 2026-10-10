import test from 'node:test';
import assert from 'node:assert/strict';

import { createApp } from '../src/app.js';
import { issueAccessToken } from '../src/services/auth.service.js';
import { roleScopes, createStore } from '../src/store.js';

delete process.env.MASTER_CRYPTO_KEY;
process.env.JWT_SECRET ??= 'test-only-jwt-secret-with-at-least-32-characters';

function tokenFor(app, userId, options = {}) {
  const membership = app.store.memberships.find(
    (item) => item.userId === userId && item.status === 'active',
  );
  return issueAccessToken(
    {
      userId,
      organizationId: membership?.organizationId ?? 'org-demo-alpha',
      scopes: roleScopes[membership?.role] ?? [],
    },
    options,
  );
}

function request(app, method, url, userId, { token, body } = {}) {
  return app.handle({
    method,
    url,
    headers: { authorization: `Bearer ${token ?? tokenFor(app, userId)}` },
    body: body ?? null,
  });
}

test('P0: JWT expirado é rejeitado com sinalização de renovação', async () => {
  const app = createApp({ store: createStore({ pool: null }) });
  const result = await request(app, 'GET', '/v1/me', 'user-admin-alpha', {
    token: tokenFor(app, 'user-admin-alpha', { expiresIn: -1 }),
  });

  assert.deepEqual(result, {
    status: 401,
    body: { error: 'TOKEN_EXPIRED', code: 'TOKEN_EXPIRED', renewalRequired: true },
  });
});

test('P0: refresh concorrente aceita uma rotação e rejeita o replay', async () => {
  const app = createApp({ store: createStore({ pool: null }) });
  const claims = {
    userId: 'user-admin-alpha',
    organizationId: 'org-demo-alpha',
    scopes: roleScopes.owner,
  };
  const refreshToken = await app.store.createRefreshToken(claims);
  const results = await Promise.all([
    app.handle({ method: 'POST', url: '/v1/auth/refresh', body: { refreshToken } }),
    app.handle({ method: 'POST', url: '/v1/auth/refresh', body: { refreshToken } }),
  ]);

  assert.deepEqual(results.map((result) => result.status).sort(), [200, 401]);
  assert.equal(results.filter((result) => result.status === 401)[0].body.error, 'REFRESH_TOKEN_INVALID');
});

test('P0: envelope E2EE de outra organização é rejeitado antes da persistência', async () => {
  const app = createApp({ store: createStore({ pool: null }) });
  const result = await request(app, 'POST', '/v1/subjects/subject-demo-child/school-collections', 'user-admin-alpha', {
    body: {
      organizationId: 'org-demo-beta',
      encryptedData: Buffer.from('ciphertext-and-authentication-tag').toString('base64'),
      iv: Buffer.alloc(12, 5).toString('base64'),
    },
  });

  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'ORGANIZATION_MISMATCH');
  assert.equal(app.store.collections.length, 0);
});

test('P0: consentimento expirado ou revogado bloqueia acesso clínico', async () => {
  const expiredApp = createApp({ store: createStore({ pool: null }) });
  const expired = await request(
    expiredApp,
    'POST',
    '/v1/subjects/subject-demo-child/consents',
    'user-admin-alpha',
    { body: {
      organizationId: 'org-demo-alpha',
      recipientUserId: 'user-professional-alpha',
      purpose: 'teste de expiração',
      scopes: ['esdm_goal.read'],
      validUntil: '2020-01-01T00:00:00.000Z',
    } },
  );
  assert.equal(expired.status, 403);
  assert.equal(expired.body.error, 'EXPIRED');

  const revokedApp = createApp({ store: createStore({ pool: null }) });
  const consent = revokedApp.store.consents.find((item) => item.id === 'consent-demo-clinic');
  consent.status = 'revoked';
  const blocked = await request(
    revokedApp,
    'GET',
    '/v1/subjects/subject-demo-child/esdm-goals',
    'user-professional-alpha',
  );
  assert.equal(blocked.status, 403);
  assert.equal(blocked.body.error, 'REVOKED');
});
