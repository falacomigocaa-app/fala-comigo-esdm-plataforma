import test from 'node:test';
import assert from 'node:assert/strict';
import { createHttpServer } from '../src/server.js';
import { createApp } from '../src/app.js';
import { createStore } from '../src/store.js';

test('HTTP health, invalid JSON, request size and login rate limit', async () => {
  const server = createHttpServer({ app: createApp({ store: createStore({ pool: null }) }), bodyLimit: 128, appOrigin: 'https://app.example.test' });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    assert.equal((await fetch(`${base}/health`)).status, 200);
    const web = await fetch(`${base}/health`, { headers: { origin: 'https://app.example.test' } });
    assert.equal(web.headers.get('access-control-allow-origin'), 'https://app.example.test');
    const outsider = await fetch(`${base}/health`, { headers: { origin: 'https://untrusted.example.test' } });
    assert.equal(outsider.headers.get('access-control-allow-origin'), null);
    assert.equal((await fetch(`${base}/v1/me`, { method: 'POST', body: '{' })).status, 400);
    assert.equal((await fetch(`${base}/v1/me`, { method: 'POST', body: 'x'.repeat(129) })).status, 413);
    for (let count = 0; count < 20; count++) {
      assert.equal((await fetch(`${base}/v1/auth/login`, { method: 'POST', body: '{' })).status, 400);
    }
    const limited = await fetch(`${base}/v1/auth/login`, { method: 'POST', body: '{}' });
    assert.equal(limited.status, 429);
    assert.equal(limited.headers.get('retry-after'), '60');
  } finally { await new Promise((resolve) => server.close(resolve)); }
});
