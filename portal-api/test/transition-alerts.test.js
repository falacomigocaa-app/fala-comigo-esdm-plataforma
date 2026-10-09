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

function payload(updatedAt) {
  return {
    alert: {
      id: 'alert-sync-1',
      title: 'Transição para banho',
      description: 'Aviso visual antes da troca de atividade',
      audioType: 'tts',
      messageText: 'Daqui a pouco vamos para o banho',
      countdownSeconds: 30,
      checklistItems: ['Guardar brinquedos'],
      isScheduled: true,
      isRecurring: true,
      isActive: true,
      advanceTime: 5,
      scheduledHour: 18,
      scheduledMinute: 0,
      scheduledWeekdays: [1, 2, 3, 4, 5],
      notificationId: 42,
      createdAt: Date.parse('2026-10-01T12:00:00.000Z'),
      updatedAt: Date.parse(updatedAt)
    },
    updatedAt
  };
}

test('owner synchronizes a transition alert without storing local media path', async () => {
  const app = createApp();
  const first = await request(app, 'POST', '/v1/subjects/subject-demo-child/transition-alerts', 'user-admin-alpha', {
    requestId: 'alert-upsert-1',
    body: payload('2026-10-08T12:00:00.000Z')
  });
  assert.equal(first.status, 201);
  assert.equal(first.body.alert.id, 'alert-sync-1');
  assert.equal('recordedAudioPath' in first.body.alert, false);

  const repeated = await request(app, 'POST', '/v1/subjects/subject-demo-child/transition-alerts', 'user-admin-alpha', {
    requestId: 'alert-upsert-1',
    body: payload('2026-10-08T12:00:00.000Z')
  });
  assert.deepEqual(repeated, first);

  const list = await request(app, 'GET', '/v1/subjects/subject-demo-child/transition-alerts', 'user-admin-alpha');
  assert.equal(list.status, 200);
  assert.equal(list.body.alerts.length, 1);
  assert.equal(list.body.alerts[0].title, 'Transição para banho');
});

test('stale transition alert update is rejected as a version conflict', async () => {
  const app = createApp();
  await request(app, 'POST', '/v1/subjects/subject-demo-child/transition-alerts', 'user-admin-alpha', {
    body: payload('2026-10-08T12:00:00.000Z')
  });
  const stale = await request(app, 'POST', '/v1/subjects/subject-demo-child/transition-alerts', 'user-admin-alpha', {
    body: payload('2026-10-08T11:00:00.000Z')
  });
  assert.equal(stale.status, 409);
  assert.equal(stale.body.error, 'VERSION_CONFLICT');
});

test('professional without routine grant cannot read transition alerts', async () => {
  const app = createApp();
  const result = await request(app, 'GET', '/v1/subjects/subject-demo-child/transition-alerts', 'user-professional-alpha');
  assert.equal(result.status, 403);
  assert.equal(result.body.error, 'GRANT_REQUIRED');
});

test('owner can delete a transition alert without affecting the local contract', async () => {
  const app = createApp();
  await request(app, 'POST', '/v1/subjects/subject-demo-child/transition-alerts', 'user-admin-alpha', {
    body: payload('2026-10-08T12:00:00.000Z')
  });
  const deleted = await request(app, 'DELETE', '/v1/subjects/subject-demo-child/transition-alerts/alert-sync-1', 'user-admin-alpha');
  assert.equal(deleted.status, 200);
  const list = await request(app, 'GET', '/v1/subjects/subject-demo-child/transition-alerts', 'user-admin-alpha');
  assert.deepEqual(list.body.alerts, []);
});
