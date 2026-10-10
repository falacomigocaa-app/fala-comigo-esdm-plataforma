import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('.', import.meta.url));
const upstream = new URL(process.env.PORTAL_API_UPSTREAM || 'http://127.0.0.1:8787');
if (upstream.protocol !== 'http:') throw new Error('Use a private HTTP API upstream behind the TLS entry point');
const types = { '.css': 'text/css; charset=utf-8', '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.json': 'application/json; charset=utf-8' };
const server = http.createServer(async (request, response) => {
  try {
    const pathname = new URL(request.url, 'http://localhost').pathname;
    if (pathname.startsWith('/api/')) {
      const target = new URL(upstream);
      target.pathname = pathname.slice(4);
      target.search = new URL(request.url, 'http://localhost').search;
      const proxy = http.request(target, { method: request.method, headers: { ...request.headers, host: upstream.host }, timeout: 30_000 }, (result) => {
        response.writeHead(result.statusCode, { ...result.headers, 'cache-control': 'no-store' }); result.pipe(response);
      });
      proxy.on('timeout', () => proxy.destroy());
      proxy.on('error', () => { if (!response.headersSent) response.writeHead(502, { 'content-type': 'application/json' }); response.end('{"error":"API_UNAVAILABLE"}'); });
      request.pipe(proxy); return;
    }
    const decoded = decodeURIComponent(pathname);
    const file = extname(decoded) ? decoded.replace(/^\/+/, '') : 'index.html';
    if (!(file === 'index.html' || file.startsWith('src/') || file.endsWith('.css'))) { response.writeHead(404); response.end(); return; }
    const candidate = resolve(root, file);
    if (!candidate.startsWith(resolve(root) + sep)) { response.writeHead(404); response.end(); return; }
    const body = await readFile(candidate);
    response.writeHead(200, {
      'content-type': types[extname(candidate)] || 'application/octet-stream',
      'x-content-type-options': 'nosniff',
      'referrer-policy': 'no-referrer',
      'content-security-policy': "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'",
      'cache-control': 'no-cache'
    });
    response.end(body);
  } catch (_) { response.writeHead(404); response.end('Not found'); }
});
server.listen(Number(process.env.PORT || 4173), '0.0.0.0', () => console.log('Portal Web ready'));
