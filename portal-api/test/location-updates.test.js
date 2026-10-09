import test from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../src/app.js';
import { issueAccessToken } from '../src/services/auth.service.js';
import { roleScopes } from '../src/store.js';

process.env.JWT_SECRET ??= 'test-only-jwt-secret-with-at-least-32-characters';

function request(app, method, url, userId, extra = {}) {
  const membership = app.store.memberships.find((item) => item.userId === userId && item.status === 'active');
  const token = issueAccessToken({
    userId,
    organizationId: membership?.organizationId ?? 'org-demo-alpha',
    scopes: roleScopes[membership?.role] ?? []
  });
  return app.handle({
    method,
    url,
    headers: {
      authorization: `Bearer ${token}`,
      ...(extra.requestId ? { 'x-request-id': extra.requestId } : {})
    },
    body: extra.body ?? null
  });
}

const envelope = (overrides = {}) => ({
  id: 'location-synthetic-1',
  organizationId: 'org-demo-alpha',
  encryptedData: Buffer.from('synthetic-ciphertext-and-auth-tag').toString('base64'),
  iv: Buffer.alloc(12, 7).toString('base64'),
  clientRecordedAt: '2026-10-09T10:00:00.000Z',
  ...overrides
});

test('owner stores only an E2EE location envelope and request is idempotent', async () => {
  const app = createApp();
  const first = await request(app, 'POST', '/v1/subjects/subject-demo-child/location-updates', 'user-admin-alpha', {
    requestId: 'location-write-1', body: envelope()
  });
  assert.equal(first.status, 201);
  assert.equal(first.body.location.encryptedData, envelope().encryptedData);
  assert.equal('latitude' in first.body.location, false);

  const repeated = await request(app, 'POST', '/v1/subjects/subject-demo-child/location-updates', 'user-admin-alpha', {
    requestId: 'location-write-1', body: envelope()
  });
  assert.deepEqual(repeated, first);

  const latest = await request(app, 'GET', '/v1/subjects/subject-demo-child/location-updates', 'user-admin-alpha');
  assert.equal(latest.status, 200);
  assert.equal(latest.body.location.id, 'location-synthetic-1');
});

test('location envelope from another organization is rejected before persistence', async () => {
  const app = createApp();
  const result = await request(app, 'POST', '/v1/subjects/subject-demo-child/location-updates', 'user-admin-alpha', {
    body: envelope({ organizationId: 'org-demo-beta' })
  });
  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'ORGANIZATION_MISMATCH');
  assert.equal(app.store.locationUpdates.length, 0);
});

test('professional without location grant cannot read or write location', async () => {
  const app = createApp();
  const read = await request(app, 'GET', '/v1/subjects/subject-demo-child/location-updates', 'user-professional-alpha');
  const write = await request(app, 'POST', '/v1/subjects/subject-demo-child/location-updates', 'user-professional-alpha', { body: envelope() });
  assert.equal(read.status, 403);
  assert.equal(write.status, 403);
  assert.equal(read.body.error, 'GRANT_REQUIRED');
});

test('owner revocation removes all encrypted location envelopes', async () => {
  const app = createApp();
  await request(app, 'POST', '/v1/subjects/subject-demo-child/location-updates', 'user-admin-alpha', { body: envelope() });
  const revoked = await request(app, 'DELETE', '/v1/subjects/subject-demo-child/location-updates/all', 'user-admin-alpha');
  assert.deepEqual(revoked.body, { revoked: true });
  const latest = await request(app, 'GET', '/v1/subjects/subject-demo-child/location-updates', 'user-admin-alpha');
  assert.equal(latest.body.location, null);
});
