import test from 'node:test';
import assert from 'node:assert/strict';
import { createDiscordNotifier, discordEmbedForReport } from '../src/services/discord-webhook.service.js';
import { createApp } from '../src/app.js';
import { issueAccessToken } from '../src/services/auth.service.js';

process.env.JWT_SECRET ??= 'test-only-jwt-secret-with-at-least-32-characters';
const authorization = `Bearer ${issueAccessToken({
  userId: 'user-admin-alpha',
  organizationId: 'org-demo-alpha',
  scopes: ['organization.read']
})}`;
const reportRequest = {
  method: 'POST',
  url: '/v1/beta/report',
  headers: {
    authorization,
    'x-client-platform': 'android',
    'x-client-version': '1.2.3',
    'x-device-model': 'Android test device'
  },
  body: {
    severity: 'sugestao',
    description: 'Seria útil manter o filtro selecionado ao voltar para a tela.'
  }
};

test('notifier Discord monta Rich Embed técnico e não permite mentions', async () => {
  let request;
  const notifier = createDiscordNotifier({
    webhookUrl: 'https://discord.com/api/webhooks/test-token',
    fetchImpl: async (url, options) => {
      request = { url, options };
      return { ok: true, status: 204 };
    }
  });
  assert.equal(notifier.enabled, true);
  const delivered = await notifier.notify({
    severity: 'sugestao',
    description: 'O filtro não permanece selecionado.',
    appVersion: '1.2.3',
    platform: 'android',
    deviceModel: 'Android test device',
    createdAt: '2026-10-10T20:00:00.000Z'
  });
  assert.equal(delivered, true);
  assert.equal(request.url, 'https://discord.com/api/webhooks/test-token');
  const payload = JSON.parse(request.options.body);
  assert.deepEqual(payload, discordEmbedForReport({
    severity: 'sugestao',
    description: 'O filtro não permanece selecionado.',
    appVersion: '1.2.3',
    platform: 'android',
    deviceModel: 'Android test device',
    createdAt: '2026-10-10T20:00:00.000Z'
  }));
  assert.deepEqual(payload.allowed_mentions, { parse: [] });
});

test('link de convite não é tratado como webhook Discord', async () => {
  let called = false;
  const notifier = createDiscordNotifier({
    webhookUrl: 'https://discord.gg/HU5K8YBtY',
    fetchImpl: async () => { called = true; return { ok: true }; }
  });
  assert.equal(notifier.enabled, false);
  assert.equal(await notifier.notify({ description: 'x', severity: 'leve' }), false);
  assert.equal(called, false);
});

test('falha do Discord não impede resposta 201 nem persistência do report', async () => {
  let called = false;
  const app = createApp({
    discordNotifier: {
      notify: async () => {
        called = true;
        throw new Error('Discord indisponível');
      }
    }
  });
  const result = await app.handle(reportRequest);
  assert.equal(result.status, 201);
  assert.equal(app.store.bugReports.length, 1);
  assert.equal(called, true);
  await new Promise((resolve) => setImmediate(resolve));
});

test('rota não aguarda o webhook para responder ao testador', async () => {
  let called = false;
  let release;
  const pending = new Promise((resolve) => { release = resolve; });
  const app = createApp({
    discordNotifier: {
      notify: () => {
        called = true;
        return pending;
      }
    }
  });
  const result = await app.handle(reportRequest);
  assert.equal(result.status, 201);
  assert.equal(called, true);
  release();
});
