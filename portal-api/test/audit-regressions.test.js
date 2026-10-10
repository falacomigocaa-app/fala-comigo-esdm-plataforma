import test from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../src/app.js';
import { createStore, roleScopes } from '../src/store.js';
import { issueAccessToken, verifyAccessToken } from '../src/services/auth.service.js';

process.env.JWT_SECRET ??= 'test-only-jwt-secret-with-at-least-32-characters';
const clock = new Date('2026-10-10T12:00:00Z');
const freshApp = () => createApp({ store: createStore({ pool: null }), now: () => clock });
function request(app, method, url, userId = 'user-admin-alpha', body, options = {}) {
  const membership = app.store.memberships.find((item) => item.userId === userId);
  const token = issueAccessToken({ userId, organizationId: options.organizationId ?? membership?.organizationId ?? 'org-demo-alpha', scopes: options.scopes ?? roleScopes[membership?.role] ?? [] });
  return app.handle({ method, url, body, headers: { authorization: `Bearer ${token}`, ...(options.requestId ? { 'x-request-id': options.requestId } : {}) } });
}
const goalPath = '/v1/subjects/subject-demo-child/esdm-goals';
const collectionPath = '/v1/subjects/subject-demo-child/school-collections';
const envelope = (organizationId) => ({ organizationId, encryptedData: Buffer.alloc(32, 1).toString('base64'), iv: Buffer.alloc(12, 2).toString('base64') });

test('default authorization clock uses current time', async () => {
  const app = createApp({ store: createStore({ pool: null }) });
  app.store.memberships[0].validUntil = new Date(Date.now() - 1000).toISOString();
  assert.equal((await request(app, 'GET', '/v1/organizations/org-demo-alpha')).status, 403);
});

test('invalid dates fail closed for membership, grant and consent', async () => {
  for (const entity of ['membership', 'grant', 'consent']) {
    const app = freshApp();
    const record = entity === 'membership' ? app.store.memberships[1] : entity === 'grant' ? app.store.grants[0] : app.store.consents[0];
    record.validUntil = 'invalid-date';
    assert.equal((await request(app, 'GET', goalPath, 'user-professional-alpha')).status, 403, entity);
  }
});

test('consent creation rejects invalid expiry', async () => {
  const result = await request(freshApp(), 'POST', '/v1/subjects/subject-demo-child/consents', 'user-admin-alpha', {
    organizationId: 'org-demo-alpha', recipientUserId: 'user-professional-alpha', scopes: ['esdm_goal.read'], purpose: 'audit', validUntil: 'not-a-date'
  });
  assert.equal(result.status, 400);
});

test('subject list respects revoked consent', async () => {
  const app = freshApp();
  app.store.consents[0].status = 'revoked';
  const result = await request(app, 'GET', '/v1/organizations/org-demo-alpha/subjects', 'user-professional-alpha');
  assert.equal(result.status, 200);
  assert.deepEqual(result.body.subjects, []);
});

test('clinical access validates current membership and JWT scopes', async () => {
  const app = freshApp();
  assert.equal((await request(app, 'GET', goalPath, 'user-admin-alpha', undefined, { scopes: [] })).status, 403);
  app.store.memberships[1].status = 'revoked';
  assert.equal((await request(app, 'GET', goalPath, 'user-professional-alpha')).status, 403);
  assert.equal((await request(freshApp(), 'GET', '/v1/organizations/org-demo-alpha/memberships', 'user-admin-alpha', undefined, { scopes: [] })).status, 403);
});

test('grant binds consent to recipient, subject, organization, purpose and scope', async () => {
  for (const [field, value] of [['recipientUserId', 'user-outsider'], ['subjectId', 'other-subject'], ['organizationId', 'org-demo-beta'], ['purpose', 'other-purpose'], ['scopes', []]]) {
    const app = freshApp();
    app.store.consents[0][field] = value;
    assert.equal((await request(app, 'GET', goalPath, 'user-professional-alpha')).status, 403, field);
  }
});

test('grant from another organization cannot authorize the active token', async () => {
  const app = freshApp();
  app.store.memberships.push({ ...app.store.memberships[1], organizationId: 'org-demo-beta' });
  const result = await request(app, 'GET', goalPath, 'user-professional-alpha', undefined, { organizationId: 'org-demo-beta' });
  assert.equal(result.status, 403);
});

test('school history returns envelopes only from active organization', async () => {
  const app = freshApp();
  await request(app, 'POST', collectionPath, 'user-admin-alpha', envelope('org-demo-alpha'));
  await request(app, 'POST', collectionPath, 'user-admin-beta', envelope('org-demo-beta'));
  const result = await request(app, 'GET', collectionPath, 'user-admin-beta');
  assert.equal(result.status, 200);
  assert.equal(result.body.collections.length, 1);
  assert.equal(result.body.collections[0].organizationId, 'org-demo-beta');
});

test('idempotency is separated by user and operation and rejects changed payload', async () => {
  const app = freshApp();
  const options = { requestId: 'same-id' };
  const first = await request(app, 'POST', '/v1/organizations/org-demo-alpha/invitations', 'user-admin-alpha', { inviteeUserId: 'user-invitee-alpha' }, options);
  const other = await request(app, 'POST', '/v1/organizations/org-demo-beta/invitations', 'user-admin-beta', { inviteeUserId: 'user-invitee-alpha' }, options);
  assert.equal(first.status, 201);
  assert.equal(other.body.organizationId, 'org-demo-beta');
  const goal = await request(app, 'POST', goalPath, 'user-admin-alpha', { codigoTecnicoDenver: 'CE_N1_I5' }, options);
  assert.equal(goal.status, 201);
  assert.ok(goal.body.goal.id.startsWith('goal-'));
  const conflict = await request(app, 'POST', goalPath, 'user-admin-alpha', { codigoTecnicoDenver: 'CE_N1_I6' }, options);
  assert.equal(conflict.status, 409);
});

test('concurrent retries execute a single persistence operation; failures can retry', async () => {
  const app = freshApp();
  let writes = 0;
  const save = app.store.saveGoal;
  app.store.saveGoal = async (...args) => { writes++; await Promise.resolve(); return save(...args); };
  const send = () => request(app, 'POST', goalPath, 'user-admin-alpha', { codigoTecnicoDenver: 'CE_N1_I5' }, { requestId: 'concurrent' });
  const [a, b] = await Promise.all([send(), send()]);
  assert.equal(writes, 1);
  assert.deepEqual(a, b);
  app.store.saveGoal = async () => { throw new Error('temporary'); };
  const retry = () => request(app, 'POST', goalPath, 'user-admin-alpha', { codigoTecnicoDenver: 'CE_N1_I5' }, { requestId: 'failure' });
  assert.equal((await retry()).status, 500);
  app.store.saveGoal = save;
  assert.equal((await retry()).status, 201);
});

test('prototype keys cannot be accepted as ESDM goal codes', async () => {
  assert.equal((await request(freshApp(), 'POST', goalPath, 'user-admin-alpha', { codigoTecnicoDenver: 'toString' })).status, 400);
});

test('login cannot bypass key endpoint scope restriction', async () => {
  const previous = process.env.MASTER_CRYPTO_KEY;
  process.env.MASTER_CRYPTO_KEY = Buffer.alloc(32, 23).toString('base64');
  try {
    const app = freshApp();
    await app.store.provisionOrganizationKey({ organizationId: 'org-demo-alpha', createdByUserId: 'user-admin-alpha' });
    const result = await app.handle({ method: 'POST', url: '/v1/auth/login', body: { email: 'profissional@fala-comigo.test', password: 'DemoPassword-2026' } });
    assert.equal(result.status, 200);
    assert.equal('organizationKey' in result.body, false);
  } finally {
    if (previous === undefined) delete process.env.MASTER_CRYPTO_KEY;
    else process.env.MASTER_CRYPTO_KEY = previous;
  }
});

test('refresh cannot renew revoked membership or restore removed role privileges', async () => {
  for (const revoked of [true, false]) {
    const app = freshApp();
    const token = await app.store.createRefreshToken({ userId: 'user-admin-alpha', organizationId: 'org-demo-alpha', scopes: roleScopes.owner }, clock);
    if (revoked) app.store.memberships[0].status = 'revoked';
    else app.store.memberships[0].role = 'professional';
    const result = await app.handle({ method: 'POST', url: '/v1/auth/refresh', body: { refreshToken: token } });
    if (revoked) assert.equal(result.status, 401);
    else {
      assert.equal(result.status, 200);
      assert.equal(verifyAccessToken(result.body.accessToken).scopes.includes('access.invite'), false);
    }
  }
});

test('invitations reject owner escalation, invalid dates and scope widening', async () => {
  for (const body of [{ role: 'owner' }, { expiresAt: 'invalid' }, { scopes: ['organization.key.read'] }, { scopes: 'esdm_goal.read' }]) {
    const result = await request(freshApp(), 'POST', '/v1/organizations/org-demo-alpha/invitations', 'user-admin-alpha', { inviteeUserId: 'user-invitee-alpha', ...body });
    assert.equal(result.status, 400);
  }
  const app = freshApp();
  const created = await request(app, 'POST', '/v1/organizations/org-demo-alpha/invitations', 'user-admin-alpha', { inviteeUserId: 'user-invitee-alpha', scopes: ['esdm_goal.read'] });
  const accepted = await request(app, 'POST', `/v1/invitations/${created.body.id}/accept`, 'user-invitee-alpha');
  assert.equal(accepted.status, 200);
  assert.deepEqual(accepted.body.membership.scopes, ['esdm_goal.read']);
  const claims = await app.store.authenticateCredentials({ email: 'invitee@fala-comigo.test', password: 'DemoPassword-2026' }, clock);
  assert.deepEqual(claims.scopes, ['esdm_goal.read']);
});

test('accepted invitation updates existing membership with explicit empty scopes', async () => {
  const app = freshApp();
  const created = await request(app, 'POST', '/v1/organizations/org-demo-alpha/invitations', 'user-admin-alpha', { inviteeUserId: 'user-professional-alpha', scopes: [] });
  const accepted = await request(app, 'POST', `/v1/invitations/${created.body.id}/accept`, 'user-professional-alpha');
  assert.equal(accepted.status, 200);
  assert.equal(app.store.memberships.filter((item) => item.userId === 'user-professional-alpha').length, 1);
  assert.deepEqual(app.store.memberships[1].scopes, []);
  assert.equal((await request(app, 'GET', goalPath, 'user-professional-alpha')).status, 403);
});

test('idempotent invitation response remains stable after acceptance', async () => {
  const app = freshApp();
  const send = () => request(app, 'POST', '/v1/organizations/org-demo-alpha/invitations', 'user-admin-alpha', { inviteeUserId: 'user-invitee-alpha' }, { requestId: 'stable-invitation' });
  const original = await send();
  await request(app, 'POST', `/v1/invitations/${original.body.id}/accept`, 'user-invitee-alpha');
  assert.deepEqual(await send(), original);
});
