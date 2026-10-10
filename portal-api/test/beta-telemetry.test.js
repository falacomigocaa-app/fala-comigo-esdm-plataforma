import test from 'node:test';
import assert from 'node:assert/strict';

import { createApp } from '../src/app.js';

test('status beta informa a data do servidor e expira após 30 dias', async () => {
  const app = createApp({ now: () => new Date('2026-11-09T00:00:00.000Z') });
  const result = await app.handle({ method: 'GET', url: '/v1/beta/status' });

  assert.equal(result.status, 200);
  assert.equal(result.body.status, 'expired');
  assert.equal(result.body.betaStartAt, '2026-10-10T00:00:00.000Z');
  assert.equal(result.body.expiresAt, '2026-11-09T00:00:00.000Z');
  assert.equal(result.body.serverNow, '2026-11-09T00:00:00.000Z');
});

test('telemetria aceita somente campos técnicos allowlistados', async () => {
  const app = createApp();
  const result = await app.handle({
    method: 'POST',
    url: '/v1/telemetry',
    body: {
      event: 'screen_view',
      platform: 'web',
      screen: '/clinica',
      email: 'profissional@example.test',
      password: 'senha-secreta',
      clinicalText: 'conteúdo confidencial'
    }
  });

  assert.equal(result.status, 202);
  assert.deepEqual(app.store.telemetryEvents[0], {
    event: 'screen_view',
    platform: 'web',
    occurredAt: app.store.telemetryEvents[0].occurredAt,
    screen: '/clinica'
  });
  assert.equal('email' in app.store.telemetryEvents[0], false);
  assert.equal('password' in app.store.telemetryEvents[0], false);
  assert.equal('clinicalText' in app.store.telemetryEvents[0], false);
});

test('telemetria rejeita evento de clique ou campo de rota arbitrário', async () => {
  const app = createApp();
  const click = await app.handle({ method: 'POST', url: '/v1/telemetry', body: { event: 'click' } });
  const screen = await app.handle({
    method: 'POST',
    url: '/v1/telemetry',
    body: { event: 'screen_view', screen: '/subject/123' }
  });

  assert.equal(click.status, 400);
  assert.equal(screen.status, 202);
  assert.equal('screen' in app.store.telemetryEvents[0], false);
});
