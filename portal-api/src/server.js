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
const allowedOrigin = process.env.PORTAL_WEB_ORIGIN ?? 'http://127.0.0.1:4173';
const corsHeaders = {
  'access-control-allow-origin': allowedOrigin,
  'access-control-allow-headers': 'accept, authorization, content-type, x-request-id, x-client-platform, x-client-version, x-device-model',
  'access-control-allow-methods': 'GET, POST, OPTIONS'
};

const server = http.createServer(async (request, response) => {
  if (request.method === 'OPTIONS') {
    response.writeHead(204, corsHeaders);
    response.end();
    return;
  }

  let body = null;
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
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
