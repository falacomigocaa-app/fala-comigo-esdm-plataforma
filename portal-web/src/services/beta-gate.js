export const BETA_START_AT = '2026-10-10T00:00:00.000Z';
export const BETA_DURATION_DAYS = 30;
const BETA_EXPIRES_AT = Date.parse(BETA_START_AT) + BETA_DURATION_DAYS * 24 * 60 * 60 * 1000;
const LAST_WALL_CLOCK_KEY = 'fala-comigo.beta.last-wall-clock';
const EXPIRES_AT_KEY = 'fala-comigo.beta.expires-at';
const MAX_CLOCK_SKEW_MS = 5 * 60 * 1000;
const DEFAULT_API_BASE = 'http://127.0.0.1:8787';
let accessPromise;

function storage() {
  return globalThis.window?.localStorage;
}

function readLocalState() {
  const local = storage();
  if (!local) return {};
  const lastWallClock = Number(local.getItem(LAST_WALL_CLOCK_KEY));
  const expiresAt = Number(local.getItem(EXPIRES_AT_KEY));
  return {
    lastWallClock: Number.isFinite(lastWallClock) && lastWallClock > 0 ? lastWallClock : null,
    expiresAt: Number.isFinite(expiresAt) && expiresAt > 0 ? expiresAt : null
  };
}

function persistLocalState({ nowMs, expiresAt }) {
  const local = storage();
  if (!local) return;
  local.setItem(LAST_WALL_CLOCK_KEY, String(nowMs));
  if (expiresAt) local.setItem(EXPIRES_AT_KEY, String(expiresAt));
}

export function evaluateBetaAccess({ nowMs = Date.now(), serverStatus = null, localState = {} } = {}) {
  const lastWallClock = localState.lastWallClock || null;
  if (lastWallClock && nowMs + MAX_CLOCK_SKEW_MS < lastWallClock) {
    return { allowed: false, reason: 'clock_rollback', expiresAt: localState.expiresAt || BETA_EXPIRES_AT };
  }
  const serverNowMs = Date.parse(serverStatus?.serverNow || '');
  const effectiveNowMs = Number.isFinite(serverNowMs) ? serverNowMs : nowMs;
  const serverExpiresAt = Date.parse(serverStatus?.expiresAt || '');
  const expiresAt = Number.isFinite(serverExpiresAt)
    ? serverExpiresAt
    : localState.expiresAt || BETA_EXPIRES_AT;
  if (serverStatus?.status === 'not_started' || effectiveNowMs < Date.parse(BETA_START_AT)) {
    return { allowed: false, reason: 'not_started', expiresAt };
  }
  if (serverStatus?.status === 'expired' || effectiveNowMs >= expiresAt) {
    return { allowed: false, reason: 'expired', expiresAt };
  }
  return { allowed: true, reason: 'active', expiresAt };
}

export async function checkBetaAccess({
  fetchImpl = globalThis.fetch,
  now = () => Date.now(),
  force = false
} = {}) {
  if (accessPromise && !force) return accessPromise;
  accessPromise = (async () => {
    const localState = readLocalState();
    const nowMs = now();
    let serverStatus = null;
    try {
      const baseUrl = (globalThis.window?.PORTAL_API_BASE || DEFAULT_API_BASE).replace(/\/$/, '');
      const response = await fetchImpl(`${baseUrl}/v1/beta/status`, {
        headers: { accept: 'application/json' },
        cache: 'no-store'
      });
      if (response.ok) serverStatus = await response.json();
    } catch (_) {
      // Offline fallback uses the last trusted expiry and clock rollback guard.
    }
    const result = evaluateBetaAccess({ nowMs, serverStatus, localState });
    persistLocalState({ nowMs, expiresAt: result.expiresAt });
    return result;
  })();
  return accessPromise;
}

export function resetBetaAccessCache() {
  accessPromise = undefined;
}
