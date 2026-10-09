import { createHmac, createHash, randomUUID, timingSafeEqual } from 'node:crypto';

export const BILLING_PLANS = Object.freeze([
  {
    id: 'essential',
    name: 'Essencial',
    description: 'Comunicação básica com privacidade e funcionamento offline.',
    monthlyPriceCents: 0,
    features: ['offlineCommunication', 'parentalControls', 'accessibility', 'localStorage'],
    publiclyVisible: true
  },
  {
    id: 'family',
    name: 'Família',
    description: 'Recursos remotos opcionais para mais de um dispositivo.',
    monthlyPriceCents: null,
    features: ['offlineCommunication', 'parentalControls', 'accessibility', 'localStorage', 'remoteBackup', 'multiDevice'],
    publiclyVisible: true
  },
  {
    id: 'connected_care',
    name: 'Cuidado Conectado',
    description: 'Vínculos autorizados com profissionais e escolas.',
    monthlyPriceCents: null,
    features: ['offlineCommunication', 'parentalControls', 'accessibility', 'localStorage', 'remoteBackup', 'multiDevice', 'careNetwork'],
    publiclyVisible: true
  },
  {
    id: 'sponsored',
    name: 'Patrocinado',
    description: 'Acesso financiado por uma instituição, sem expor conteúdo familiar.',
    monthlyPriceCents: null,
    features: ['offlineCommunication', 'parentalControls', 'accessibility', 'localStorage', 'remoteBackup', 'multiDevice', 'sponsoredLicense'],
    publiclyVisible: true
  },
  {
    id: 'organization',
    name: 'Organização',
    description: 'Portal administrativo e benefícios sem conteúdo familiar.',
    monthlyPriceCents: 0,
    features: ['accessibility', 'organizationPortal', 'benefitAdministration', 'aggregateReporting', 'prioritySupport'],
    publiclyVisible: false
  }
]);

const planById = new Map(BILLING_PLANS.map((plan) => [plan.id, plan]));
const SANDBOX_PRICES = Object.freeze({ family: 1990, connected_care: 3990, sponsored: 0 });

export class BillingError extends Error {
  constructor(code, status = 400) {
    super(code);
    this.name = 'BillingError';
    this.code = code;
    this.status = status;
  }
}

export function publicPlans() {
  return BILLING_PLANS.filter((plan) => plan.publiclyVisible);
}

export function getPlan(planId) {
  const plan = planById.get(planId);
  if (!plan) throw new BillingError('PLAN_NOT_FOUND', 404);
  return plan;
}

export function assertCheckoutPlan(planId) {
  const plan = getPlan(planId);
  if (plan.id === 'essential' || plan.id === 'organization') {
    throw new BillingError('PLAN_NOT_CHECKOUTABLE', 400);
  }
  if (!(plan.id in SANDBOX_PRICES)) throw new BillingError('PLAN_PRICE_NOT_CONFIGURED', 409);
  return plan;
}

export function createSandboxCheckout({ organizationId, userId, planId, now = new Date() }) {
  const plan = assertCheckoutPlan(planId);
  return {
    id: `checkout_${randomUUID()}`,
    organizationId,
    userId,
    planId: plan.id,
    provider: 'sandbox',
    status: 'pending_payment',
    mode: 'test',
    amountCents: SANDBOX_PRICES[plan.id],
    currency: 'BRL',
    createdAt: now.toISOString(),
    expiresAt: new Date(now.getTime() + 30 * 60 * 1000).toISOString(),
    checkoutUrl: null
  };
}

export function signSandboxWebhook(payload, secret = process.env.BILLING_WEBHOOK_SECRET) {
  if (!secret) throw new BillingError('BILLING_WEBHOOK_SECRET_REQUIRED', 503);
  const serialized = typeof payload === 'string' ? payload : JSON.stringify(payload);
  return createHmac('sha256', secret).update(serialized).digest('hex');
}

export function verifySandboxWebhook(payload, signature) {
  if (typeof signature !== 'string' || !signature.trim()) {
    throw new BillingError('WEBHOOK_SIGNATURE_REQUIRED', 401);
  }
  const expected = signSandboxWebhook(payload);
  const expectedBuffer = Buffer.from(expected, 'utf8');
  const receivedBuffer = Buffer.from(signature.trim(), 'utf8');
  if (expectedBuffer.length !== receivedBuffer.length ||
      !timingSafeEqual(expectedBuffer, receivedBuffer)) {
    throw new BillingError('WEBHOOK_SIGNATURE_INVALID', 401);
  }
}

export function hashBillingPayload(payload) {
  return createHash('sha256').update(JSON.stringify(payload)).digest('hex');
}
