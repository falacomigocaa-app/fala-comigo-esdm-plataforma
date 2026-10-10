import test from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../src/app.js';
import { issueAccessToken } from '../src/services/auth.service.js';
import { roleScopes, createStore } from '../src/store.js';

delete process.env.MASTER_CRYPTO_KEY;
process.env.JWT_SECRET ??= 'test-only-jwt-secret-with-at-least-32-characters';

function tokenFor(app, userId) {
  const membership = app.store.memberships.find((item) => item.userId === userId && item.status === 'active');
  return issueAccessToken({
    userId,
    organizationId: membership?.organizationId ?? 'org-demo-alpha',
    scopes: roleScopes[membership?.role] ?? []
  });
}

function request(app, method, url, userId, extra = {}) {
  return app.handle({
    method,
    url,
    headers: {
      authorization: `Bearer ${tokenFor(app, userId)}`,
      ...(extra.requestId ? {'x-request-id': extra.requestId} : {})
    },
    body: extra.body ?? null
  });
}

async function clearSchoolCollections(app) {
  if (app.store.pool) {
    await app.store.pool.query('delete from school_collections where subject_id = $1', ['subject-demo-child']);
    return;
  }
  app.store.collections.length = 0;
}

test('owner reads its own organization', async () => {
  const app = createApp({ store: createStore({ pool: null }) });
  const result = await request(app, 'GET', '/v1/organizations/org-demo-alpha', 'user-admin-alpha');
  assert.equal(result.status, 200);
  assert.equal(result.body.id, 'org-demo-alpha');
});

test('cross-organization read is denied without revealing the other tenant', async () => {
  const app = createApp({ store: createStore({ pool: null }) });
  const result = await request(app, 'GET', '/v1/organizations/org-demo-beta', 'user-admin-alpha');
  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'RELATIONSHIP_REQUIRED');
  assert.deepEqual(Object.keys(result.body), ['error']);
});

test('outsider cannot read an organization', async () => {
  const app = createApp({ store: createStore({ pool: null }) });
  const result = await request(app, 'GET', '/v1/organizations/org-demo-alpha', 'user-outsider');
  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'RELATIONSHIP_REQUIRED');
});

test('professional cannot create an invitation', async () => {
  const app = createApp({ store: createStore({ pool: null }) });
  const result = await request(app, 'POST', '/v1/organizations/org-demo-alpha/invitations', 'user-professional-alpha', {
    requestId: 'request-professional-invite',
    body: { inviteeUserId: 'user-invitee-alpha', role: 'professional' }
  });
  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'SCOPE_DENIED');
});

test('owner can create an invitation and repeated request is idempotent', async () => {
  const app = createApp({ store: createStore({ pool: null }) });
  const extra = { requestId: 'request-create-invite', body: { inviteeUserId: 'user-invitee-alpha', role: 'professional' } };
  const first = await request(app, 'POST', '/v1/organizations/org-demo-alpha/invitations', 'user-admin-alpha', extra);
  const second = await request(app, 'POST', '/v1/organizations/org-demo-alpha/invitations', 'user-admin-alpha', extra);
  assert.equal(first.status, 201);
  assert.deepEqual(second, first);
  assert.equal(app.store.invitations.filter((item) => item.id === first.body.id).length, 1);
});

test('pending invitation does not grant organization access', async () => {
  const app = createApp({ store: createStore({ pool: null }) });
  const result = await request(app, 'GET', '/v1/organizations/org-demo-alpha', 'user-invitee-alpha');
  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'RELATIONSHIP_REQUIRED');
});

test('expired invitation cannot be accepted', async () => {
  const app = createApp({ store: createStore({ pool: null }) });
  const result = await request(app, 'POST', '/v1/invitations/invite-alpha-expired/accept', 'user-invitee-alpha');
  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'EXPIRED');
});

test('benefit access does not expose family content', async () => {
  const app = createApp({ store: createStore({ pool: null }) });
  const result = await request(app, 'GET', '/v1/organizations/org-demo-alpha/benefits', 'user-admin-alpha');
  assert.equal(result.status, 200);
  assert.deepEqual(Object.keys(result.body), ['benefits']);
  assert.equal('subjects' in result.body, false);
});

test('missing JWT is rejected', async () => {
  const app = createApp({ store: createStore({ pool: null }) });
  const result = await app.handle({ method: 'GET', url: '/v1/me', headers: {} });
  assert.equal(result.status, 401);
  assert.equal(result.body.error, 'AUTH_REQUIRED');
});

test('revoked membership cannot read organization', async () => {
  const app = createApp({ store: createStore({ pool: null }) });
  app.store.memberships.push({
    id: 'membership-revoked-alpha',
    userId: 'user-admin-beta',
    organizationId: 'org-demo-alpha',
    role: 'org_admin',
    status: 'revoked',
    validUntil: '2099-01-01T00:00:00.000Z'
  });
  const result = await request(app, 'GET', '/v1/organizations/org-demo-alpha', 'user-admin-beta');
  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'REVOKED');
});

test('expired membership cannot read organization', async () => {
  const app = createApp({ store: createStore({ pool: null }) });
  app.store.memberships.push({
    id: 'membership-expired-alpha',
    userId: 'user-outsider',
    organizationId: 'org-demo-alpha',
    role: 'org_admin',
    status: 'expired',
    validUntil: '2020-01-01T00:00:00.000Z'
  });
  const result = await request(app, 'GET', '/v1/organizations/org-demo-alpha', 'user-outsider');
  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'EXPIRED');
});

test('audit events do not contain sensitive payloads', async () => {
  const app = createApp({ store: createStore({ pool: null }) });
  await request(app, 'GET', '/v1/organizations/org-demo-alpha', 'user-admin-alpha');
  const event = app.store.auditEvents.at(-1);
  assert.equal(event.result, 'allowed');
  assert.equal('password' in event, false);
  assert.equal('token' in event, false);
  assert.equal('payload' in event, false);
});


test('owner creates scoped consent for a child subject', async () => {
  const app = createApp({ store: createStore({ pool: null }) });
  const result = await request(app, 'POST', '/v1/subjects/subject-demo-child/consents', 'user-admin-alpha', {
    body: {
      organizationId: 'org-demo-alpha',
      recipientUserId: 'user-invitee-alpha',
      purpose: 'coordenação da comunicação',
      scopes: ['communication_profile.read', 'tasks.read'],
      validUntil: '2026-12-31T00:00:00.000Z',
      noticeVersion: 'synthetic-v1'
    }
  });
  assert.equal(result.status, 201);
  assert.equal(result.body.subjectId, 'subject-demo-child');
  assert.deepEqual(result.body.scopes, ['communication_profile.read', 'tasks.read']);
});

test('consent is required before a subject invitation', async () => {
  const app = createApp({ store: createStore({ pool: null }) });
  const result = await request(app, 'POST', '/v1/organizations/org-demo-alpha/invitations', 'user-admin-alpha', {
    body: { inviteeUserId: 'user-invitee-alpha', subjectId: 'subject-demo-child', role: 'professional' }
  });
  assert.equal(result.status, 400);
  assert.equal(result.body.error, 'CONSENT_REQUIRED');
});

test('accepted scoped invitation creates a grant and permits subject read', async () => {
  const app = createApp({ store: createStore({ pool: null }) });
  const consent = await request(app, 'POST', '/v1/subjects/subject-demo-child/consents', 'user-admin-alpha', {
    body: {
      organizationId: 'org-demo-alpha', recipientUserId: 'user-invitee-alpha',
      purpose: 'coordenação da comunicação', scopes: ['communication_profile.read'],
      validUntil: '2026-12-31T00:00:00.000Z'
    }
  });
  const invitation = await request(app, 'POST', '/v1/organizations/org-demo-alpha/invitations', 'user-admin-alpha', {
    body: { inviteeUserId: 'user-invitee-alpha', subjectId: 'subject-demo-child', consentId: consent.body.id, role: 'caregiver' }
  });
  const accepted = await request(app, 'POST', `/v1/invitations/${invitation.body.id}/accept`, 'user-invitee-alpha');
  assert.equal(accepted.status, 200);
  assert.equal(accepted.body.grant.consentId, consent.body.id);
  const read = await request(app, 'GET', '/v1/subjects/subject-demo-child', 'user-invitee-alpha');
  assert.equal(read.status, 200);
  assert.equal(read.body.id, 'subject-demo-child');
});

test('revoked grant immediately blocks subject read', async () => {
  const app = createApp({ store: createStore({ pool: null }) });
  const consent = await request(app, 'POST', '/v1/subjects/subject-demo-child/consents', 'user-admin-alpha', {
    body: {
      organizationId: 'org-demo-alpha', recipientUserId: 'user-invitee-alpha',
      purpose: 'coordenação da comunicação', scopes: ['communication_profile.read'],
      validUntil: '2026-12-31T00:00:00.000Z'
    }
  });
  const invitation = await request(app, 'POST', '/v1/organizations/org-demo-alpha/invitations', 'user-admin-alpha', {
    body: { inviteeUserId: 'user-invitee-alpha', subjectId: 'subject-demo-child', consentId: consent.body.id, role: 'caregiver' }
  });
  const accepted = await request(app, 'POST', `/v1/invitations/${invitation.body.id}/accept`, 'user-invitee-alpha');
  const revoked = await request(app, 'POST', `/v1/subjects/subject-demo-child/grants/${accepted.body.grant.id}/revoke`, 'user-admin-alpha');
  assert.equal(revoked.status, 200);
  const read = await request(app, 'GET', '/v1/subjects/subject-demo-child', 'user-invitee-alpha');
  assert.equal(read.status, 403);
  assert.equal(read.body.error, 'GRANT_REQUIRED');
});

test('subject owner can read the subject without a remote grant', async () => {
  const app = createApp({ store: createStore({ pool: null }) });
  const result = await request(app, 'GET', '/v1/subjects/subject-demo-child', 'user-admin-alpha');
  assert.equal(result.status, 200);
  assert.equal(result.body.ownerUserId, 'user-admin-alpha');
});

test('school collection accepts and persists an E2EE envelope without plaintext', async () => {
  const app = createApp({ store: createStore({ pool: null }) });
  await clearSchoolCollections(app);
  const envelope = {
    organizationId: 'org-demo-alpha',
    encryptedData: Buffer.from('ciphertext-and-authentication-tag').toString('base64'),
    iv: Buffer.alloc(12, 7).toString('base64')
  };
  const result = await request(app, 'POST', '/v1/subjects/subject-demo-child/school-collections', 'user-admin-alpha', { body: envelope });

  assert.equal(result.status, 201);
  assert.equal(result.body.collection.organizationId, envelope.organizationId);
  assert.equal(result.body.collection.encryptedData, envelope.encryptedData);
  assert.equal(result.body.collection.iv, envelope.iv);
  assert.equal(result.body.collection.blocoRotinaEscolar, null);
  const persisted = await app.store.getCollectionsBySubject('subject-demo-child', 'org-demo-alpha');
  assert.equal(persisted.length, 1);
  assert.equal(persisted[0].encryptedData, envelope.encryptedData);
  assert.equal('ciphertext-and-authentication-tag' in persisted[0], false);
});

test('school collection rejects an envelope from another organization', async () => {
  const app = createApp({ store: createStore({ pool: null }) });
  await clearSchoolCollections(app);
  const result = await request(app, 'POST', '/v1/subjects/subject-demo-child/school-collections', 'user-admin-alpha', {
    body: {
      organizationId: 'org-demo-beta',
      encryptedData: Buffer.from('cross-tenant-secret').toString('base64'),
      iv: Buffer.alloc(12, 8).toString('base64')
    }
  });

  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'ORGANIZATION_MISMATCH');
  assert.equal((await app.store.getCollectionsBySubject('subject-demo-child', 'org-demo-alpha')).length, 0);
});

test('school collection rejects malformed E2EE envelope', async () => {
  const app = createApp({ store: createStore({ pool: null }) });
  const result = await request(app, 'POST', '/v1/subjects/subject-demo-child/school-collections', 'user-admin-alpha', {
    body: { organizationId: 'org-demo-alpha', encryptedData: 'not-enough', iv: 'short' }
  });

  assert.equal(result.status, 400);
  assert.equal(result.body.error, 'INVALID_E2EE_ENVELOPE');
});

test('organization owner can provision and read only the unwrapped organization key', async () => {
  const previousMasterKey = process.env.MASTER_CRYPTO_KEY;
  process.env.MASTER_CRYPTO_KEY = Buffer.alloc(32, 23).toString('base64');
  try {
    const app = createApp({ store: createStore({ pool: null }) });
    await app.store.provisionOrganizationKey({ organizationId: 'org-demo-alpha', createdByUserId: 'user-admin-alpha' });
    const result = await request(app, 'GET', '/v1/organizations/org-demo-alpha/keys', 'user-admin-alpha');

    assert.equal(result.status, 200);
    assert.equal(result.body.organizationId, 'org-demo-alpha');
    assert.equal(Buffer.from(result.body.organizationKey, 'base64').length, 32);
    assert.equal('keyEncrypted' in result.body, false);
  } finally {
    if (previousMasterKey === undefined) delete process.env.MASTER_CRYPTO_KEY;
    else process.env.MASTER_CRYPTO_KEY = previousMasterKey;
  }
});

test('professional without organization.key.read cannot read organization key', async () => {
  const previousMasterKey = process.env.MASTER_CRYPTO_KEY;
  process.env.MASTER_CRYPTO_KEY = Buffer.alloc(32, 23).toString('base64');
  try {
    const app = createApp({ store: createStore({ pool: null }) });
    await app.store.provisionOrganizationKey({ organizationId: 'org-demo-alpha', createdByUserId: 'user-admin-alpha' });
    const result = await request(app, 'GET', '/v1/organizations/org-demo-alpha/keys', 'user-professional-alpha');

    assert.equal(result.status, 403);
    assert.equal(result.body.error, 'SCOPE_DENIED');
  } finally {
    if (previousMasterKey === undefined) delete process.env.MASTER_CRYPTO_KEY;
    else process.env.MASTER_CRYPTO_KEY = previousMasterKey;
  }
});

test('organization key endpoint denies a member from a different organization', async () => {
  const previousMasterKey = process.env.MASTER_CRYPTO_KEY;
  process.env.MASTER_CRYPTO_KEY = Buffer.alloc(32, 23).toString('base64');
  try {
    const app = createApp({ store: createStore({ pool: null }) });
    await app.store.provisionOrganizationKey({ organizationId: 'org-demo-beta', createdByUserId: 'user-admin-beta' });
    const result = await request(app, 'GET', '/v1/organizations/org-demo-beta/keys', 'user-admin-alpha');

    assert.equal(result.status, 403);
    assert.equal(result.body.error, 'RELATIONSHIP_REQUIRED');
  } finally {
    if (previousMasterKey === undefined) delete process.env.MASTER_CRYPTO_KEY;
    else process.env.MASTER_CRYPTO_KEY = previousMasterKey;
  }
});
