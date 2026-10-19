import http from 'node:http';
import { createApp } from './app.js';
import { createDiscordNotifier } from './services/discord-webhook.service.js';

if (process.env.NODE_ENV === 'production') {
  if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL must be configured in production');
  if (!process.env.JWT_SECRET || process.env.JWT_SECRET.length < 32) {
    throw new Error('JWT_SECRET must be configured with at least 32 characters in production');
  }
  if (!process.env.MASTER_CRYPTO_KEY || process.env.MASTER_CRYPTO_KEY.length < 32) {
    throw new Error('MASTER_CRYPTO_KEY must be configured in production');
  }
}

const discordWebhookUrl = process.env.DISCORD_WEBHOOK_URL?.trim() || '';
const app = createApp({
  discordNotifier: createDiscordNotifier({ webhookUrl: discordWebhookUrl })
});
const maxBodyBytes = Number(process.env.MAX_BODY_BYTES ?? 1_048_576);
const rateWindowMs = Number(process.env.RATE_LIMIT_WINDOW_MS ?? 60_000);
const rateLimits = new Map();
const routeLimits = new Map([
  ['/v1/auth/login', 10],
  ['/v1/auth/refresh', 20],
  ['/v1/telemetry', 30],
  ['/v1/beta/report', 10]
]);
const allowedOrigin = process.env.PORTAL_WEB_ORIGIN ?? 'http://127.0.0.1:4173';
const corsHeaders = {
  'access-control-allow-origin': allowedOrigin,
  'access-control-allow-headers': 'accept, authorization, content-type, x-request-id, x-client-platform, x-client-version, x-device-model',
  'access-control-allow-methods': 'GET, POST, OPTIONS',
  'access-control-allow-credentials': 'true',
  'vary': 'Origin',
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'no-referrer',
  'x-frame-options': 'DENY',
  ...(process.env.NODE_ENV === 'production' ? { 'strict-transport-security': 'max-age=31536000; includeSubDomains' } : {})
};
function clientAddress(request) {
  return String(request.headers['x-forwarded-for'] ?? request.socket.remoteAddress ?? 'unknown').split(',')[0].trim();
}
function rateLimitExceeded(request, pathname) {
  const limit = routeLimits.get(pathname);
  if (!limit) return false;
  const key = `${clientAddress(request)}:${pathname}`;
  const now = Date.now();
  const current = rateLimits.get(key);
  if (!current || now - current.startedAt >= rateWindowMs) {
    rateLimits.set(key, { startedAt: now, count: 1 });
    return false;
  }
  current.count += 1;
  return current.count > limit;
}
const server = http.createServer(async (request, response) => {
  request.setTimeout(Number(process.env.REQUEST_TIMEOUT_MS ?? 15_000));
  const pathname = new URL(request.url ?? '/', 'http://localhost').pathname;
  if (request.method === 'OPTIONS') {
    response.writeHead(204, corsHeaders);
    response.end();
    return;
  }
  if (request.method === 'GET' && pathname === '/healthz') {
    response.writeHead(200, { ...corsHeaders, 'content-type': 'application/json; charset=utf-8' });
    response.end(JSON.stringify({ status: 'ok' }));
    return;
  }
  if (request.method === 'GET' && pathname === '/readyz') {
    const ready = Boolean(app.store.pool && app.store.persistAuthorization);
    response.writeHead(ready ? 200 : 503, { ...corsHeaders, 'content-type': 'application/json; charset=utf-8' });
    response.end(JSON.stringify({ status: ready ? 'ready' : 'not_ready', storage: app.store.storageMode }));
    return;
  }
  if (rateLimitExceeded(request, pathname)) {
    response.writeHead(429, { ...corsHeaders, 'content-type': 'application/json; charset=utf-8', 'retry-after': String(Math.ceil(rateWindowMs / 1000)) });
    response.end(JSON.stringify({ error: 'RATE_LIMITED' }));
    return;
  }
  const declaredLength = Number(request.headers['content-length'] ?? 0);
  if (declaredLength > maxBodyBytes) {
    response.writeHead(413, { ...corsHeaders, 'content-type': 'application/json; charset=utf-8' });
    response.end(JSON.stringify({ error: 'PAYLOAD_TOO_LARGE' }));
    return;
  }
  let body = null;
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    const chunks = [];
    let receivedBytes = 0;
    for await (const chunk of request) {
      receivedBytes += chunk.length;
      if (receivedBytes > maxBodyBytes) {
        response.writeHead(413, { ...corsHeaders, 'content-type': 'application/json; charset=utf-8' });
        response.end(JSON.stringify({ error: 'PAYLOAD_TOO_LARGE' }));
        request.destroy();
        return;
      }
      chunks.push(chunk);
    }
    if (chunks.length > 0) {
      try {
        body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      } catch (_) {
        response.writeHead(400, { ...corsHeaders, 'content-type': 'application/json; charset=utf-8' });
        response.end(JSON.stringify({ error: 'INVALID_JSON' }));
        return;
      }
    }
  }

  const headers = Object.fromEntries(Object.entries(request.headers).map(([key, value]) => [key.toLowerCase(), value]));
  const result = await app.handle({ method: request.method, url: request.url, headers, body });
  response.writeHead(result.status, { ...corsHeaders, 'content-type': 'application/json; charset=utf-8' });
  response.end(JSON.stringify(result.body));
});

const port = Number(process.env.PORT ?? 8787);
const host = process.env.HOST ?? '127.0.0.1';
server.listen(port, host, () => {
  console.log(`Fala Comigo portal API local: http://${host}:${port}`);
});
