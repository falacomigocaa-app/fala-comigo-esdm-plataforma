import test from 'node:test';
import assert from 'node:assert/strict';

function installBrowser(fetchImpl, session = { userId: 'user-professional-alpha', organizationId: 'org-demo-alpha', token: 'jwt-test-token' }) {
  globalThis.window = {
    PORTAL_API_BASE: 'http://127.0.0.1:8787',
    sessionStorage: {
      getItem: () => JSON.stringify(session),
      setItem: () => {},
      removeItem: () => {}
    },
    dispatchEvent: () => true
  };
  globalThis.fetch = fetchImpl;
}

test('APIClient envia Authorization Bearer, request id e carrega metas/coletas reais', async () => {
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
    assert.equal(request.options.headers.authorization, 'Bearer jwt-test-token');
    assert.equal('x-synthetic-user-id' in request.options.headers, false);
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

test('APIClient limpa a sessão e sinaliza reautenticação em 401', async () => {
  let removed = false;
  let signaled = false;
  installBrowser(async () => ({
    ok: false,
    status: 401,
    async json() { return { error: 'TOKEN_EXPIRED', renewalRequired: true }; }
  }));
  window.sessionStorage.removeItem = () => { removed = true; };
  window.dispatchEvent = () => { signaled = true; return true; };

  const { APIClient } = await import(`../src/api/client.js?case=${Date.now()}`);
  await assert.rejects(
    () => new APIClient().carregarHistoricoEscolar('subject-demo-child'),
    (error) => error.status === 401 && error.renewalRequired === true
  );
  assert.equal(removed, true);
  assert.equal(signaled, true);
});

test('APIClient renova a sessão e repete a requisição após TOKEN_EXPIRED', async () => {
  const session = {
    userId: 'user-professional-alpha',
    organizationId: 'org-demo-alpha',
    token: 'access-old',
    refreshToken: 'refresh-old'
  };
  const requests = [];
  let persisted;
  globalThis.window = {
    PORTAL_API_BASE: 'http://127.0.0.1:8787',
    sessionStorage: {
      getItem: () => JSON.stringify(persisted || session),
      setItem: (_key, value) => { persisted = JSON.parse(value); },
      removeItem: () => {}
    },
    dispatchEvent: () => true
  };
  globalThis.fetch = async (url, options) => {
    requests.push({ url, options });
    if (url.endsWith('/v1/auth/refresh')) {
      return {
        ok: true,
        status: 200,
        async json() { return { accessToken: 'access-new', refreshToken: 'refresh-new', expiresIn: 900 }; }
      };
    }
    if (requests.length === 1) {
      return {
        ok: false,
        status: 401,
        async json() { return { error: 'TOKEN_EXPIRED', renewalRequired: true }; }
      };
    }
    return { ok: true, status: 200, async json() { return { goals: [] }; } };
  };

  const { APIClient } = await import(`../src/api/client.js?case=${Date.now()}`);
  const result = await new APIClient().carregarMetas('subject-demo-child');

  assert.deepEqual(result, { goals: [] });
  assert.equal(requests.length, 3);
  assert.equal(requests[0].options.headers.authorization, 'Bearer access-old');
  assert.deepEqual(JSON.parse(requests[1].options.body), { refreshToken: 'refresh-old' });
  assert.equal(requests[2].options.headers.authorization, 'Bearer access-new');
  assert.equal(persisted.token, 'access-new');
  assert.equal(persisted.refreshToken, 'refresh-new');
});

test('APIClient compartilha um único refresh em requisições clínicas paralelas', async () => {
  const session = {
    userId: 'user-professional-alpha',
    organizationId: 'org-demo-alpha',
    token: 'access-expired',
    refreshToken: 'refresh-seven-days'
  };
  let persisted;
  let refreshCalls = 0;
  let expiredCalls = 0;
  let retriedCalls = 0;
  globalThis.window = {
    PORTAL_API_BASE: 'http://127.0.0.1:8787',
    sessionStorage: {
      getItem: () => JSON.stringify(persisted || session),
      setItem: (_key, value) => { persisted = JSON.parse(value); },
      removeItem: () => {}
    },
    dispatchEvent: () => true
  };
  globalThis.fetch = async (url, options) => {
    if (url.endsWith('/v1/auth/refresh')) {
      refreshCalls += 1;
      await new Promise((resolve) => setTimeout(resolve, 15));
      return {
        ok: true,
        status: 200,
        async json() { return { accessToken: 'access-recovered', refreshToken: 'refresh-rotated', expiresIn: 900 }; }
      };
    }
    if (options.headers.authorization === 'Bearer access-expired') {
      expiredCalls += 1;
      return {
        ok: false,
        status: 401,
        async json() { return { error: 'TOKEN_EXPIRED', renewalRequired: true }; }
      };
    }
    retriedCalls += 1;
    assert.equal(options.headers.authorization, 'Bearer access-recovered');
    return url.endsWith('/esdm-goals')
      ? { ok: true, status: 200, async json() { return { goals: ['recovered-goal'] }; } }
      : { ok: true, status: 200, async json() { return { collections: ['recovered-collection'] }; } };
  };

  const { APIClient } = await import(`../src/api/client.js?case=${Date.now()}`);
  const client = new APIClient();
  const [goals, collections] = await Promise.all([
    client.carregarMetas('subject-demo-child'),
    client.carregarHistoricoEscolar('subject-demo-child')
  ]);

  assert.deepEqual(goals, { goals: ['recovered-goal'] });
  assert.deepEqual(collections, { collections: ['recovered-collection'] });
  assert.equal(expiredCalls, 2);
  assert.equal(refreshCalls, 1);
  assert.equal(retriedCalls, 2);
  assert.equal(persisted.token, 'access-recovered');
  assert.equal(persisted.refreshToken, 'refresh-rotated');
});

test('APIClient.login envia email e senha ao provedor central', async () => {
  let request;
  installBrowser(async (url, options) => {
    request = { url, options };
    return {
      ok: true,
      status: 200,
      async json() {
        return {
          userId: 'user-professional-alpha',
          organizationId: 'org-demo-alpha',
          scopes: ['esdm_goal.read'],
          accessToken: 'access-login',
          refreshToken: 'refresh-login'
        };
      }
    };
  });

  const { APIClient } = await import(`../src/api/client.js?case=${Date.now()}`);
  const result = await new APIClient().login(
    ' profissional@fala-comigo.test ',
    'DemoPassword-2026'
  );

  assert.equal(request.url, 'http://127.0.0.1:8787/v1/auth/login');
  assert.equal(request.options.method, 'POST');
  assert.deepEqual(JSON.parse(request.options.body), {
    email: ' profissional@fala-comigo.test ',
    password: 'DemoPassword-2026'
  });
  assert.equal(result.accessToken, 'access-login');
});

test('refresh atrasado não restaura sessão encerrada', async () => {
  let session = { token: 'old-token', refreshToken: 'old-refresh' };
  let finish;
  installBrowser(() => new Promise((resolve) => { finish = resolve; }));
  window.sessionStorage = {
    getItem: () => JSON.stringify(session),
    setItem: (_, value) => { session = JSON.parse(value); },
    removeItem: () => { session = null; }
  };
  const { APIClient, clearSession } = await import('../src/api/client.js');
  const pending = new APIClient().refreshSession();
  clearSession();
  finish({ ok: true, status: 200, json: async () => ({ accessToken: 'new-token', refreshToken: 'new-refresh' }) });
  await assert.rejects(pending, /SESSION_CHANGED/);
  assert.equal(session, null);
});
