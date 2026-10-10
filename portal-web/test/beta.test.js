import test from 'node:test';
import assert from 'node:assert/strict';
import { evaluateBetaAccess } from '../src/services/beta-gate.js';
import { buildTelemetryPayload } from '../src/services/telemetry.js';

test('telemetria aceita somente evento técnico e não transporta texto de formulário', () => {
  const payload = buildTelemetryPayload('screen_view', {
    screen: '/clinica',
    email: 'profissional@example.test',
    password: 'senha-secreta',
    clinicalText: 'informação sensível'
  });
  assert.deepEqual(Object.keys(payload).sort(), ['event', 'occurredAt', 'platform', 'screen', 'sessionId'].sort());
  assert.equal('email' in payload, false);
  assert.equal('password' in payload, false);
  assert.equal('clinicalText' in payload, false);
  assert.equal(buildTelemetryPayload('click', { screen: '/clinica' }), null);
});

test('trava beta bloqueia uma data expirada usando a autoridade do backend', () => {
  const status = evaluateBetaAccess({
    nowMs: Date.parse('2026-11-10T00:00:01.000Z'),
    serverStatus: {
      status: 'expired',
      serverNow: '2026-11-10T00:00:01.000Z',
      expiresAt: '2026-11-09T23:59:59.999Z'
    }
  });
  assert.deepEqual(status, {
    allowed: false,
    reason: 'expired',
    expiresAt: Date.parse('2026-11-09T23:59:59.999Z')
  });
});

test('trava beta bloqueia fraude de retrocesso do relógio local', () => {
  const status = evaluateBetaAccess({
    nowMs: Date.parse('2026-10-12T00:00:00.000Z'),
    localState: {
      lastWallClock: Date.parse('2026-10-20T00:00:00.000Z'),
      expiresAt: Date.parse('2026-11-09T00:00:00.000Z')
    }
  });
  assert.equal(status.allowed, false);
  assert.equal(status.reason, 'clock_rollback');
});
