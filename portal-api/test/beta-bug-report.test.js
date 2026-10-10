import test from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../src/app.js';
import { issueAccessToken } from '../src/services/auth.service.js';

process.env.JWT_SECRET ??= 'test-only-jwt-secret-with-at-least-32-characters';
const claims = {
  userId: 'user-admin-alpha',
  organizationId: 'org-demo-alpha',
  scopes: ['organization.read']
};
const authorization = `Bearer ${issueAccessToken(claims)}`;

function report(app, body, extraHeaders = {}) {
  return app.handle({
    method: 'POST',
    url: '/v1/beta/report',
    headers: {
      authorization,
      'user-agent': 'TestBrowser/1.0',
      'x-client-platform': 'web',
      'x-client-version': 'web-test-1.0',
      ...extraHeaders
    },
    body
  });
}

test('report de bug aceita somente metadados técnicos e persiste no isolamento beta', async () => {
  const app = createApp();
  const result = await report(app, {
    severity: 'travamento',
    description: 'A tela de metas fica sem resposta após tocar em atualizar.'
  });
  assert.equal(result.status, 201);
  assert.equal(result.body.accepted, true);
  assert.equal(app.store.bugReports.length, 1);
  assert.deepEqual(app.store.bugReports[0], {
    id: result.body.reportId,
    userId: 'user-admin-alpha',
    organizationId: 'org-demo-alpha',
    severity: 'travamento',
    description: 'A tela de metas fica sem resposta após tocar em atualizar.',
    appVersion: 'web-test-1.0',
    platform: 'web',
    userAgent: 'TestBrowser/1.0',
    deviceModel: '',
    createdAt: app.store.bugReports[0].createdAt
  });
});

test('report de bug exige autenticação', async () => {
  const result = await createApp().handle({
    method: 'POST',
    url: '/v1/beta/report',
    body: { severity: 'leve', description: 'Botão não responde.' }
  });
  assert.deepEqual(result, { status: 401, body: { error: 'AUTH_REQUIRED' } });
});

test('report rejeita texto com dados de prontuário ou identificadores clínicos', async () => {
  const app = createApp();
  for (const description of [
    'Meu e-mail é pessoa@example.com e o botão falhou.',
    'CPF 123.456.789-09 aparece no formulário.',
    'O prontuário do paciente foi exibido na tela.'
  ]) {
    const result = await report(app, { severity: 'leve', description });
    assert.deepEqual(result, { status: 400, body: { error: 'BUG_REPORT_PRIVACY_VIOLATION' } });
  }
  assert.equal(app.store.bugReports.length, 0);
});

test('report rejeita severidade inválida e descrição vazia', async () => {
  const app = createApp();
  assert.deepEqual(await report(app, { severity: 'alta', description: 'Falha técnica.' }), {
    status: 400,
    body: { error: 'INVALID_BUG_REPORT' }
  });
  assert.deepEqual(await report(app, { severity: 'leve', description: '   ' }), {
    status: 400,
    body: { error: 'INVALID_BUG_REPORT' }
  });
});
