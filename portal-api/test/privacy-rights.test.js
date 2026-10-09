import test from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../src/app.js';
import { issueAccessToken } from '../src/services/auth.service.js';
import { roleScopes } from '../src/store.js';

process.env.JWT_SECRET ??= 'test-only-jwt-secret-with-at-least-32-characters';

function ownerHeaders(app) {
  const token = issueAccessToken({
    userId: 'user-admin-alpha',
    organizationId: 'org-demo-alpha',
    scopes: roleScopes.owner
  });
  return { authorization: `Bearer ${token}` };
}

test('titular lista e revoga consentimento explicitamente', async () => {
  const app = createApp();
  const consent = await app.handle({
    method: 'POST',
    url: '/v1/subjects/subject-demo-child/consents',
    headers: ownerHeaders(app),
    body: {
      organizationId: 'org-demo-alpha',
      recipientUserId: 'user-professional-alpha',
      purpose: 'teste fechado sintético',
      scopes: ['location.read'],
      noticeVersion: 'privacy-v1',
      validUntil: '2099-01-01T00:00:00.000Z'
    }
  });
  assert.equal(consent.status, 201);
  const listed = await app.handle({
    method: 'GET',
    url: '/v1/subjects/subject-demo-child/consents',
    headers: ownerHeaders(app)
  });
  assert.equal(listed.status, 200);
  assert.equal(listed.body.consents.some((item) => item.id === consent.body.id), true);
  const revoked = await app.handle({
    method: 'POST',
    url: `/v1/subjects/subject-demo-child/consents/${consent.body.id}/revoke`,
    headers: ownerHeaders(app)
  });
  assert.equal(revoked.status, 200);
  assert.equal(revoked.body.consent.status, 'revoked');
});

test('exportação retorna somente metadados e exclusão revoga dados remotos', async () => {
  const app = createApp();
  const exported = await app.handle({
    method: 'GET',
    url: '/v1/subjects/subject-demo-child/privacy/export',
    headers: ownerHeaders(app)
  });
  assert.equal(exported.status, 200);
  assert.equal(exported.body.encryptedContent, true);
  assert.equal('encryptedData' in exported.body, false);
  assert.equal(typeof exported.body.categories.consents, 'number');

  const deleted = await app.handle({
    method: 'DELETE',
    url: '/v1/subjects/subject-demo-child/privacy/data',
    headers: ownerHeaders(app)
  });
  assert.equal(deleted.status, 200);
  assert.equal(deleted.body.deleted, true);
  assert.equal(app.store.consents.every((consent) => consent.status !== 'active'), true);
  assert.equal(app.store.grants.every((grant) => grant.status !== 'active'), true);
});

test('consentimento rejeita destinatário inexistente e escopo desconhecido', async () => {
  const app = createApp();
  const result = await app.handle({
    method: 'POST',
    url: '/v1/subjects/subject-demo-child/consents',
    headers: ownerHeaders(app),
    body: {
      organizationId: 'org-demo-alpha',
      recipientUserId: 'missing-user',
      purpose: 'inválido',
      scopes: ['admin.superpower']
    }
  });
  assert.equal(result.status, 400);
  assert.equal(result.body.error, 'INVALID_CONSENT');
});
