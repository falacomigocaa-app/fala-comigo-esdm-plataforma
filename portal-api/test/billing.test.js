import test from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../src/app.js';
import { issueAccessToken } from '../src/services/auth.service.js';
import { roleScopes } from '../src/store.js';
import { signSandboxWebhook } from '../src/services/billing.service.js';

process.env.JWT_SECRET ??= 'test-only-jwt-secret-with-at-least-32-characters';
process.env.BILLING_WEBHOOK_SECRET = 'sandbox-only-secret';

function ownerHeaders(app) {
  const membership = app.store.memberships.find((item) => item.userId === 'user-admin-alpha');
  const token = issueAccessToken({
    userId: 'user-admin-alpha',
    organizationId: membership.organizationId,
    scopes: roleScopes.owner
  });
  return { authorization: `Bearer ${token}` };
}

async function resetBilling(app) {
  if (app.store.pool) {
    await app.store.pool.query('delete from billing_events');
    await app.store.pool.query('delete from subscriptions');
  }
}

test('catálogo público expõe somente planos visíveis e modo sandbox', async () => {
  const result = await createApp().handle({ method: 'GET', url: '/v1/plans' });
  assert.equal(result.status, 200);
  assert.equal(result.body.billingMode, 'sandbox');
  assert.deepEqual(result.body.plans.map((plan) => plan.id), [
    'essential', 'family', 'connected_care', 'sponsored'
  ]);
});

test('checkout sandbox cria assinatura pendente sem dados de pagamento', async () => {
  const app = createApp();
  await resetBilling(app);
  const result = await app.handle({
    method: 'POST',
    url: '/v1/billing/checkout',
    headers: ownerHeaders(app),
    body: { planId: 'family' }
  });
  assert.equal(result.status, 201);
  assert.equal(result.body.checkout.provider, 'sandbox');
  assert.equal(result.body.checkout.status, 'pending_payment');
  assert.equal(result.body.checkout.amountCents, 1990);
  assert.equal(result.body.checkout.checkoutUrl, null);
  assert.equal(result.body.subscription.status, 'pending_payment');
  assert.equal('cardNumber' in result.body.checkout, false);
});

test('webhook assinado ativa assinatura e replay é idempotente', async () => {
  const app = createApp();
  await resetBilling(app);
  const checkout = await app.handle({
    method: 'POST',
    url: '/v1/billing/checkout',
    headers: ownerHeaders(app),
    body: { planId: 'connected_care' }
  });
  const event = {
    id: 'evt_sandbox_001',
    type: 'checkout.completed',
    data: {
      organizationId: 'org-demo-alpha',
      providerSubscriptionId: 'sandbox_sub_001'
    }
  };
  const headers = { 'x-billing-signature': signSandboxWebhook(event) };
  const first = await app.handle({ method: 'POST', url: '/v1/billing/webhooks/sandbox', headers, body: event });
  assert.equal(first.status, 202);
  assert.equal(first.body.subscription.status, 'active');
  const replay = await app.handle({ method: 'POST', url: '/v1/billing/webhooks/sandbox', headers, body: event });
  assert.equal(replay.status, 200);
  assert.equal(replay.body.duplicate, true);
  const current = await app.handle({ method: 'GET', url: '/v1/billing/subscription', headers: ownerHeaders(app) });
  assert.equal(current.body.subscription.planId, checkout.body.checkout.planId);
  assert.equal(current.body.subscription.status, 'active');
});

test('webhook sem assinatura válida é rejeitado', async () => {
  const result = await createApp().handle({
    method: 'POST',
    url: '/v1/billing/webhooks/sandbox',
    headers: { 'x-billing-signature': 'invalid' },
    body: { id: 'evt-invalid', type: 'checkout.completed', data: {} }
  });
  assert.equal(result.status, 401);
  assert.equal(result.body.error, 'WEBHOOK_SIGNATURE_INVALID');
});
