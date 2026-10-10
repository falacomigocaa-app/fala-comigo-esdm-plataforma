import http from 'node:http';
import { pathToFileURL } from 'node:url';
import { createApp } from './app.js';

export function createHttpServer({ app = createApp(), allowedOrigin = process.env.PORTAL_WEB_ORIGIN ?? 'http://127.0.0.1:4173', appOrigin = process.env.PORTAL_APP_ORIGIN, bodyLimit = 1024 * 1024 } = {}) {
  const attempts = new Map();
  const server = http.createServer(async (request, response) => {
    const headers = {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
      ...([allowedOrigin, appOrigin].filter(Boolean).includes(request.headers.origin)
        ? { 'access-control-allow-origin': request.headers.origin } : {}),
      'access-control-allow-headers': 'accept, authorization, content-type, x-request-id',
      'access-control-allow-methods': 'GET, POST, OPTIONS',
      vary: 'Origin'
    };
    const send = (status, body) => { response.writeHead(status, headers); response.end(JSON.stringify(body)); };
    try {
      const path = new URL(request.url, 'http://localhost').pathname;
      if (request.method === 'OPTIONS') { send(204, null); return; }
      if (path === '/health' && request.method === 'GET') {
        if (app.store.pool) await app.store.database.query('select 1');
        send(200, { status: 'ok' }); return;
      }
      if (['/v1/auth/login', '/v1/auth/activate', '/v1/auth/password'].includes(path) && request.method === 'POST') {
        const now = Date.now();
        for (const [key, entry] of attempts) if (entry.until <= now) attempts.delete(key);
        const key = request.socket.remoteAddress;
        const entry = attempts.get(key) ?? { count: 0, until: now + 60_000 };
        if (entry.count >= 20 || (!attempts.has(key) && attempts.size >= 10_000)) {
          headers['retry-after'] = '60'; send(429, { error: 'TOO_MANY_ATTEMPTS' }); return;
        }
        entry.count += 1; attempts.set(key, entry);
      }
      const declared = Number(request.headers['content-length'] ?? 0);
      if (declared > bodyLimit) { send(413, { error: 'BODY_TOO_LARGE' }); return; }
      let size = 0;
      const chunks = [];
      for await (const chunk of request) {
        size += chunk.length;
        if (size > bodyLimit) { send(413, { error: 'BODY_TOO_LARGE' }); return; }
        chunks.push(chunk);
      }
      let body = null;
      if (size) {
        try { body = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
        catch (_) { send(400, { error: 'INVALID_JSON' }); return; }
      }
      const result = await app.handle({ method: request.method, url: request.url, headers: request.headers, body });
      send(result.status, result.body);
    } catch (_) {
      if (!response.headersSent && !response.destroyed) send(500, { error: 'INTERNAL_ERROR' });
    }
  });
  server.requestTimeout = 30_000;
  server.headersTimeout = 15_000;
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (!process.env.JWT_SECRET || process.env.JWT_SECRET.length < 32) throw new Error('JWT_SECRET must have at least 32 characters');
  if (process.env.NODE_ENV === 'production') {
    if (!process.env.DATABASE_URL || !process.env.MASTER_CRYPTO_KEY) throw new Error('Production requires DATABASE_URL and MASTER_CRYPTO_KEY');
    const origin = new URL(process.env.PORTAL_WEB_ORIGIN);
    if (origin.protocol !== 'https:') throw new Error('Production requires an HTTPS portal origin');
    if (process.env.PORTAL_APP_ORIGIN && new URL(process.env.PORTAL_APP_ORIGIN).protocol !== 'https:') throw new Error('Production requires an HTTPS app origin');
  }
  const server = createHttpServer();
  server.listen(Number(process.env.PORT ?? 8787), process.env.HOST ?? '127.0.0.1', () => console.log('Portal API ready'));
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.close(() => process.exit(0)));
}
