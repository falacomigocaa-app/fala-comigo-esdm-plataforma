import test from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../src/app.js';

function request(app, method, url, userId, extra = {}) {
  return app.handle({
    method,
    url,
    headers: {
      'x-synthetic-user-id': userId,
      ...(extra.requestId ? {'x-request-id': extra.requestId} : {})
    },
    body: extra.body ?? null
  });
}

test('owner reads its own organization', async () => {
  const app = createApp();
  const result = await request(app, 'GET', '/v1/organizations/org-demo-alpha', 'user-admin-alpha');
  assert.equal(result.status, 200);
  assert.equal(result.body.id, 'org-demo-alpha');
});

test('cross-organization read is denied without revealing the other tenant', async () => {
  const app = createApp();
  const result = await request(app, 'GET', '/v1/organizations/org-demo-beta', 'user-admin-alpha');
  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'RELATIONSHIP_REQUIRED');
  assert.deepEqual(Object.keys(result.body), ['error']);
});

test('outsider cannot read an organization', async () => {
  const app = createApp();
  const result = await request(app, 'GET', '/v1/organizations/org-demo-alpha', 'user-outsider');
  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'RELATIONSHIP_REQUIRED');
});

test('professional cannot create an invitation', async () => {
  const app = createApp();
  const result = await request(app, 'POST', '/v1/organizations/org-demo-alpha/invitations', 'user-professional-alpha', {
    requestId: 'request-professional-invite',
    body: { inviteeUserId: 'user-invitee-alpha', role: 'professional' }
  });
  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'SCOPE_DENIED');
});

test('owner can create an invitation and repeated request is idempotent', async () => {
  const app = createApp();
  const extra = { requestId: 'request-create-invite', body: { inviteeUserId: 'user-invitee-alpha', role: 'professional' } };
  const first = await request(app, 'POST', '/v1/organizations/org-demo-alpha/invitations', 'user-admin-alpha', extra);
  const second = await request(app, 'POST', '/v1/organizations/org-demo-alpha/invitations', 'user-admin-alpha', extra);
  assert.equal(first.status, 201);
  assert.deepEqual(second, first);
  assert.equal(app.store.invitations.filter((item) => item.id === first.body.id).length, 1);
});

test('pending invitation does not grant organization access', async () => {
  const app = createApp();
  const result = await request(app, 'GET', '/v1/organizations/org-demo-alpha', 'user-invitee-alpha');
  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'RELATIONSHIP_REQUIRED');
});

test('expired invitation cannot be accepted', async () => {
  const app = createApp();
  const result = await request(app, 'POST', '/v1/invitations/invite-alpha-expired/accept', 'user-invitee-alpha');
  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'EXPIRED');
});

test('benefit access does not expose family content', async () => {
  const app = createApp();
  const result = await request(app, 'GET', '/v1/organizations/org-demo-alpha/benefits', 'user-admin-alpha');
  assert.equal(result.status, 200);
  assert.deepEqual(Object.keys(result.body), ['benefits']);
  assert.equal('subjects' in result.body, false);
});

test('missing synthetic identity is rejected', async () => {
  const app = createApp();
  const result = await app.handle({ method: 'GET', url: '/v1/me', headers: {} });
  assert.equal(result.status, 401);
  assert.equal(result.body.error, 'AUTH_REQUIRED');
});

test('revoked membership cannot read organization', async () => {
  const app = createApp();
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
  const app = createApp();
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
  const app = createApp();
  await request(app, 'GET', '/v1/organizations/org-demo-alpha', 'user-admin-alpha');
  const event = app.store.auditEvents.at(-1);
  assert.equal(event.result, 'allowed');
  assert.equal('password' in event, false);
  assert.equal('token' in event, false);
  assert.equal('payload' in event, false);
});


test('owner creates scoped consent for a child subject', async () => {
  const app = createApp();
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
  const app = createApp();
  const result = await request(app, 'POST', '/v1/organizations/org-demo-alpha/invitations', 'user-admin-alpha', {
    body: { inviteeUserId: 'user-invitee-alpha', subjectId: 'subject-demo-child', role: 'professional' }
  });
  assert.equal(result.status, 400);
  assert.equal(result.body.error, 'CONSENT_REQUIRED');
});

test('accepted scoped invitation creates a grant and permits subject read', async () => {
  const app = createApp();
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
  const app = createApp();
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
  const app = createApp();
  const result = await request(app, 'GET', '/v1/subjects/subject-demo-child', 'user-admin-alpha');
  assert.equal(result.status, 200);
  assert.equal(result.body.ownerUserId, 'user-admin-alpha');
});
