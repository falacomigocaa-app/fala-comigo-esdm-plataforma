import test from 'node:test';
import assert from 'node:assert/strict';

function installBrowser(fetchImpl, session = { userId: 'user-professional-alpha', organizationId: 'org-demo-alpha' }) {
  globalThis.window = {
    PORTAL_API_BASE: 'http://127.0.0.1:8787',
    localStorage: {
      getItem: () => JSON.stringify(session),
      setItem: () => {},
      removeItem: () => {}
    }
  };
  globalThis.fetch = fetchImpl;
}

test('APIClient envia identidade sintética, request id e carrega metas/coletas reais', async () => {
  const requests = [];
  installBrowser(async (url, options) => {
    requests.push({ url, options });
    return {
      ok: true,
      status: 200,
      async json() {
        return url.endsWith('/esdm-goals') ? { goals: [{ codigoTecnicoDenver: 'CE_N1_I5' }] } : { collections: [] };
      }
    };
  });

  const { APIClient } = await import(`../src/api/client.js?case=${Date.now()}`);
  const client = new APIClient();
  await client.carregarMetas('subject-demo-child');
  await client.carregarHistoricoEscolar('subject-demo-child');

  assert.equal(requests[0].url, 'http://127.0.0.1:8787/v1/subjects/subject-demo-child/esdm-goals');
  assert.equal(requests[1].url, 'http://127.0.0.1:8787/v1/subjects/subject-demo-child/school-collections');
  for (const request of requests) {
    assert.equal(request.options.headers['x-synthetic-user-id'], 'user-professional-alpha');
    assert.equal(typeof request.options.headers['x-request-id'], 'string');
    assert.ok(request.options.headers['x-request-id'].length > 0);
  }
});

test('APIClient salva uma meta com POST JSON no endpoint parametrizado', async () => {
  let request;
  installBrowser(async (url, options) => {
    request = { url, options };
    return { ok: true, status: 201, async json() { return { goal: { id: 'goal-1' } }; } };
  });

  const { APIClient } = await import(`../src/api/client.js?case=${Date.now()}`);
  const client = new APIClient();
  await client.salvarMeta('subject/demo', { codigoTecnicoDenver: 'CE_N1_I6' });

  assert.equal(request.url, 'http://127.0.0.1:8787/v1/subjects/subject%2Fdemo/esdm-goals');
  assert.equal(request.options.method, 'POST');
  assert.equal(request.options.headers['content-type'], 'application/json');
  assert.deepEqual(JSON.parse(request.options.body), { codigoTecnicoDenver: 'CE_N1_I6' });
});

test('APIClient propaga erro HTTP com código estável para a interface', async () => {
  installBrowser(async () => ({
    ok: false,
    status: 403,
    async json() { return { error: 'SCOPE_DENIED' }; }
  }));

  const { APIClient } = await import(`../src/api/client.js?case=${Date.now()}`);
  await assert.rejects(
    () => new APIClient().carregarHistoricoEscolar('subject-demo-child'),
    (error) => error.message === 'SCOPE_DENIED' && error.status === 403
  );
});
