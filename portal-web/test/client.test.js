import test from 'node:test';
import assert from 'node:assert/strict';

function installBrowser(fetchImpl, session = { userId: 'user-professional-alpha', organizationId: 'org-demo-alpha', token: 'jwt-test-token' }) {
  globalThis.window = {
    PORTAL_API_BASE: 'http://127.0.0.1:8787',
    localStorage: {
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
  window.localStorage.removeItem = () => { removed = true; };
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
    localStorage: {
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
    localStorage: {
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

function mutableBrowser(fetchImpl) {
  let session = { userId: 'user-alpha', organizationId: 'org-alpha', token: 'access-old', refreshToken: 'refresh-old' };
  installBrowser(fetchImpl);
  window.localStorage.getItem = () => JSON.stringify(session);
  window.localStorage.setItem = (_key, value) => { session = JSON.parse(value); };
  window.localStorage.removeItem = () => { session = null; };
  return { read: () => session, write: (value) => { session = value; } };
}
const expiredResponse = () => ({ ok: false, status: 401, async json() { return { error: 'TOKEN_EXPIRED', renewalRequired: true }; } });
const refreshedResponse = () => ({ ok: true, status: 200, async json() { return { accessToken: 'access-new', refreshToken: 'refresh-new' }; } });

test('late 401 reuses an already rotated token and retains POST request id', async () => {
  let releaseLate;
  const lateResponse = new Promise((resolve) => { releaseLate = resolve; });
  let refreshCalls = 0;
  const requests = [];
  mutableBrowser(async (url, options) => {
    requests.push({ url, options });
    if (url.endsWith('/refresh')) { refreshCalls++; return refreshedResponse(); }
    if (options.headers.authorization === 'Bearer access-old') {
      if (url.includes('school-collections')) return lateResponse;
      return expiredResponse();
    }
    return { ok: true, status: 200, async json() { return {}; } };
  });
  const { APIClient } = await import(`../src/api/client.js?late=${Date.now()}`);
  const client = new APIClient();
  const late = client.salvarColeta('subject-a', { encryptedData: 'test' });
  await client.carregarMetas('subject-a');
  releaseLate(expiredResponse());
  await late;
  assert.equal(refreshCalls, 1);
  const posts = requests.filter((r) => r.url.includes('school-collections'));
  assert.equal(posts.length, 2);
  assert.equal(posts[0].options.headers['x-request-id'], posts[1].options.headers['x-request-id']);
});

test('refresh finishing after logout cannot restore the old session', async () => {
  let releaseRefresh;
  let refreshStarted;
  const started = new Promise((resolve) => { refreshStarted = resolve; });
  const pending = new Promise((resolve) => { releaseRefresh = resolve; });
  const browser = mutableBrowser(async (url) => {
    if (url.endsWith('/refresh')) { refreshStarted(); return pending; }
    return expiredResponse();
  });
  const { APIClient } = await import(`../src/api/client.js?logout=${Date.now()}`);
  const request = new APIClient().carregarMetas('subject-a');
  const rejected = assert.rejects(request);
  await started;
  browser.write(null);
  releaseRefresh(refreshedResponse());
  await rejected;
  assert.equal(browser.read(), null);
});

test('old unauthorized response cannot clear a newer login', async () => {
  let release;
  const pending = new Promise((resolve) => { release = resolve; });
  const browser = mutableBrowser(() => pending);
  const { APIClient } = await import(`../src/api/client.js?switched=${Date.now()}`);
  const request = new APIClient().carregarMetas('subject-a');
  const rejected = assert.rejects(request, /SESSION_CHANGED/);
  const next = { userId: 'user-beta', organizationId: 'org-beta', token: 'beta', refreshToken: 'beta-refresh' };
  browser.write(next);
  release(expiredResponse());
  await rejected;
  assert.deepEqual(browser.read(), next);
});

test('APIClient.login preserves the invalid credentials error', async () => {
  installBrowser(async () => ({ ok: false, status: 401, async json() { return { error: 'INVALID_CREDENTIALS' }; } }));
  const { APIClient } = await import(`../src/api/client.js?login-error=${Date.now()}`);
  await assert.rejects(() => new APIClient().login('synthetic@example.test', 'wrong'), (error) => error.message === 'INVALID_CREDENTIALS' && error.status === 401);
});

test('new login refresh cannot join an older session refresh', async () => {
  let oldStarted;
  let releaseOld;
  const started = new Promise((resolve) => { oldStarted = resolve; });
  const oldResponse = new Promise((resolve) => { releaseOld = resolve; });
  const browser = mutableBrowser(async (_url, options) => {
    const body = JSON.parse(options.body);
    if (body.refreshToken === 'refresh-old') { oldStarted(); return oldResponse; }
    return { ok: true, status: 200, async json() { return { accessToken: 'beta-new', refreshToken: 'beta-rotated' }; } };
  });
  const { APIClient } = await import(`../src/api/client.js?new-login-refresh=${Date.now()}`);
  const client = new APIClient();
  const old = client.refreshSession();
  const rejected = assert.rejects(old, /SESSION_CHANGED/);
  await started;
  browser.write({ userId: 'user-beta', organizationId: 'org-beta', token: 'beta-expired', refreshToken: 'beta-refresh' });
  await client.refreshSession();
  releaseOld(refreshedResponse());
  await rejected;
  assert.equal(browser.read().userId, 'user-beta');
  assert.equal(browser.read().token, 'beta-new');
});
