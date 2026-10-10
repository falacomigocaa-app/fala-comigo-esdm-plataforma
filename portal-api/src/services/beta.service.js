const DEFAULT_BETA_START_AT = '2026-10-10T00:00:00.000Z';
const DEFAULT_BETA_DURATION_DAYS = 30;

export function betaConfig(env = process.env) {
  const startAt = env.BETA_START_AT || DEFAULT_BETA_START_AT;
  const durationDays = Math.min(365, Math.max(1, Number(env.BETA_DURATION_DAYS || DEFAULT_BETA_DURATION_DAYS)));
  const start = new Date(startAt);
  if (Number.isNaN(start.getTime())) throw new Error('INVALID_BETA_START_AT');
  return {
    start,
    durationDays,
    expiresAt: new Date(start.getTime() + durationDays * 24 * 60 * 60 * 1000),
    bypassEmails: new Set(String(env.BETA_BYPASS_EMAILS || '').split(',').map((email) => email.trim().toLowerCase()).filter(Boolean))
  };
}

export function isBetaBypassEmail(email, env = process.env) {
  const normalized = typeof email === 'string' ? email.trim().toLowerCase() : '';
  return normalized.length > 0 && betaConfig(env).bypassEmails.has(normalized);
}

export function betaWindow(now = new Date(), env = process.env) {
  const config = betaConfig(env);
  const serverNow = new Date(now);
  const status = serverNow < config.start ? 'not_started' : serverNow >= config.expiresAt ? 'expired' : 'active';
  return {
    status,
    betaStartAt: config.start.toISOString(),
    expiresAt: config.expiresAt.toISOString(),
    serverNow: serverNow.toISOString(),
    server_time: serverNow.toISOString()
  };
}

export function assertBetaAccess(email, now = new Date(), env = process.env) {
  const window = betaWindow(now, env);
  const bypass = isBetaBypassEmail(email, env);
  if (window.status === 'expired' && !bypass) {
    const error = new Error('BETA_PERIOD_EXPIRED');
    error.code = 'BETA_PERIOD_EXPIRED';
    error.status = 403;
    throw error;
  }
  return { ...window, betaBypass: bypass };
}
