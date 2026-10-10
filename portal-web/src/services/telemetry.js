const SAFE_EVENTS = new Set(['screen_view', 'beta_expired', 'sync_success', 'sync_failed']);
const SAFE_SCREENS = new Set(['/login', '/clinica', '/escola', '/relatorios', '/admin/profissionais']);
const DEFAULT_API_BASE = 'http://127.0.0.1:8787';
const sessionId = globalThis.crypto?.randomUUID?.() || `web-${Date.now()}-${Math.random().toString(16).slice(2)}`;

function apiBase() {
  return (globalThis.window?.PORTAL_API_BASE || DEFAULT_API_BASE).replace(/\/$/, '');
}

export function buildTelemetryPayload(event, { screen, reason } = {}) {
  if (!SAFE_EVENTS.has(event)) return null;
  const payload = {
    event,
    sessionId,
    platform: 'web',
    occurredAt: new Date().toISOString()
  };
  if (event === 'screen_view' && SAFE_SCREENS.has(screen)) payload.screen = screen;
  if (event === 'beta_expired' && ['expired', 'clock_rollback', 'not_started'].includes(reason)) {
    payload.reason = reason;
  }
  return payload;
}

export async function trackTelemetry(event, details = {}, { fetchImpl = globalThis.fetch } = {}) {
  const payload = buildTelemetryPayload(event, details);
  if (!payload || typeof fetchImpl !== 'function') return false;
  try {
    await fetchImpl(`${apiBase()}/v1/telemetry`, {
      method: 'POST',
      headers: { accept: 'application/json', 'content-type': 'application/json' },
      body: JSON.stringify(payload),
      keepalive: true
    });
    return true;
  } catch (_) {
    // Telemetry never blocks communication, login, or offline features.
    return false;
  }
}

export { SAFE_EVENTS, SAFE_SCREENS };
