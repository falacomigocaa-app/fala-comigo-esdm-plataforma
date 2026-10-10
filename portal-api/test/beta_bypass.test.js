import test from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../src/app.js';
import { issueAccessToken } from '../src/services/auth.service.js';

process.env.JWT_SECRET ??= 'test-only-jwt-secret-with-at-least-32-characters';
const adminClaims = { userId: 'user-admin-alpha', organizationId: 'org-demo-alpha', scopes: ['organization.read'] };
const token = () => issueAccessToken(adminClaims);
const original = {
  start: process.env.BETA_START_AT,
  duration: process.env.BETA_DURATION_DAYS,
  bypass: process.env.BETA_BYPASS_EMAILS
};
function restore() {
  for (const [key, value] of Object.entries({ BETA_START_AT: original.start, BETA_DURATION_DAYS: original.duration, BETA_BYPASS_EMAILS: original.bypass })) {
    if (value === undefined) delete process.env[key]; else process.env[key] = value;
  }
}

test.afterEach(restore);

test('usuário comum dentro dos 30 dias é permitido', async () => {
  process.env.BETA_START_AT = '2026-10-01T00:00:00.000Z';
  process.env.BETA_DURATION_DAYS = '30';
  delete process.env.BETA_BYPASS_EMAILS;
  const result = await createApp({ now: () => new Date('2026-10-20T00:00:00.000Z') }).handle({
    method: 'GET', url: '/v1/me', headers: { authorization: `Bearer ${token()}` }
  });
  assert.equal(result.status, 200);
});

test('usuário comum depois dos 30 dias recebe BETA_PERIOD_EXPIRED', async () => {
  process.env.BETA_START_AT = '2026-09-01T00:00:00.000Z';
  process.env.BETA_DURATION_DAYS = '30';
  delete process.env.BETA_BYPASS_EMAILS;
  const result = await createApp({ now: () => new Date('2026-10-20T00:00:00.000Z') }).handle({
    method: 'GET', url: '/v1/me', headers: { authorization: `Bearer ${token()}` }
  });
  assert.deepEqual(result, { status: 403, body: { error: 'BETA_PERIOD_EXPIRED' } });
});

test('múltiplos e-mails administrativos ultrapassam a expiração', async () => {
  process.env.BETA_START_AT = '2026-09-01T00:00:00.000Z';
  process.env.BETA_DURATION_DAYS = '30';
  process.env.BETA_BYPASS_EMAILS = 'outro-admin@example.test, admin@fala-comigo.test';
  const result = await createApp({ now: () => new Date('2026-10-20T00:00:00.000Z') }).handle({
    method: 'GET', url: '/v1/me', headers: { authorization: `Bearer ${token()}` }
  });
  assert.equal(result.status, 200);
});

test('rollback do relógio local é bloqueado no cliente', async () => {
  const { evaluateBetaAccess } = await import('../../portal-web/src/services/beta-gate.js');
  const result = evaluateBetaAccess({
    nowMs: Date.parse('2026-10-12T00:00:00.000Z'),
    localState: { lastWallClock: Date.parse('2026-10-20T00:00:00.000Z'), expiresAt: Date.parse('2026-11-09T00:00:00.000Z') }
  });
  assert.equal(result.allowed, false);
  assert.equal(result.reason, 'clock_rollback');
});
