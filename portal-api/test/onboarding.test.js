import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { createApp } from '../src/app.js';
import { createStore, roleScopes } from '../src/store.js';
import { issueAccessToken } from '../src/services/auth.service.js';
process.env.JWT_SECRET = randomBytes(48).toString('hex');
const password = 'Local-activation-password-2026';
const actor = (id = 'user-admin-alpha', role = 'owner') => ({ authorization: `Bearer ${issueAccessToken({ userId: id, organizationId: 'org-demo-alpha', scopes: roleScopes[role] })}` });
const setup = () => createApp({ store: createStore({ pool: null }) });
const invite = (app, extra = {}) => app.handle({ method: 'POST', url: '/v1/organizations/org-demo-alpha/account-invitations', headers: actor(), body: { email: 'new@example.test', role: 'professional', ...extra } });

test('conta só é ativada por token de uso único; vínculo conserva escopos mínimos', async () => {
  const app = setup();
  const created = await invite(app, { scopes: ['organization.read', 'access.read', 'esdm_goal.read'] });
  assert.equal(created.status, 201);
  assert.equal(app.store.activationTokens[0].id.includes(created.body.token), false);
  const login = () => app.handle({ method: 'POST', url: '/v1/auth/login', body: { email: 'new@example.test', password } });
  assert.equal((await login()).status, 401);
  const activate = () => app.handle({ method: 'POST', url: '/v1/auth/activate', body: { token: created.body.token, password } });
  const results = await Promise.all([activate(), activate()]);
  assert.deepEqual(results.map((r) => r.status).sort(), [200, 400]);
  const authenticated = await login();
  assert.equal(authenticated.status, 200);
  assert.ok(authenticated.body.scopes.includes('esdm_goal.read'));
  assert.ok(!authenticated.body.scopes.includes('esdm_goal.write'));
  assert.ok(!authenticated.body.scopes.includes('organization.key.read'));
});

test('convite inválido, escopo elevado e token expirado falham fechado', async () => {
  const app = setup();
  assert.equal((await invite(app, { scopes: ['access.invite'] })).status, 400);
  const created = await invite(app);
  assert.equal(created.status, 201);
  assert.equal((await invite(app)).status, 409);
  app.store.activationTokens[0].expiresAt = '2000-01-01';
  assert.equal((await app.handle({ method: 'POST', url: '/v1/auth/activate', body: { token: created.body.token, password } })).status, 400);
});

test('cadastro exige responsabilidade e consentimento limita e revoga acesso clínico', async () => {
  const app = setup();
  const create = (body) => app.handle({ method: 'POST', url: '/v1/subjects', headers: actor(), body });
  assert.equal((await create({ displayName: 'Pessoa sintética' })).status, 400);
  const created = await create({ displayName: 'Pessoa sintética', guardianConfirmed: true });
  assert.equal(created.status, 201);
  const id = created.body.subject.id;
  const read = () => app.handle({ method: 'GET', url: `/v1/subjects/${id}/esdm-goals`, headers: actor('user-professional-alpha', 'professional') });
  assert.equal((await read()).status, 403);
  const access = await app.handle({ method: 'POST', url: `/v1/subjects/${id}/access`, headers: actor(), body: { recipientUserId: 'user-professional-alpha', scopes: ['esdm_goal.read'], purpose: 'Acompanhar metas', validUntil: new Date(Date.now() + 86400000).toISOString(), consentConfirmed: true } });
  assert.equal(access.status, 201);
  assert.equal((await read()).status, 200);
  const write = await app.handle({ method: 'POST', url: `/v1/subjects/${id}/esdm-goals`, headers: actor('user-professional-alpha', 'professional'), body: { codigoTecnicoDenver: 'CE_N1_I5' } });
  assert.equal(write.status, 403);
  const revoked = await app.handle({ method: 'POST', url: `/v1/subjects/${id}/grants/${access.body.grant.id}/revoke`, headers: actor() });
  assert.equal(revoked.status, 200);
  assert.equal((await read()).status, 403);
});

test('alteração de vínculo remove escopos mesmo com JWT anterior e protege titular', async () => {
  const app = setup();
  const update = (id, body) => app.handle({ method: 'POST', url: `/v1/organizations/org-demo-alpha/member-access/${id}`, headers: actor(), body });
  const body = { status: 'active', role: 'professional', scopes: ['esdm_goal.read'], validUntil: new Date(Date.now() + 86400000).toISOString() };
  assert.equal((await update('membership-admin-alpha', body)).status, 403);
  assert.equal((await update('membership-professional-alpha', body)).status, 200);
  const denied = await app.handle({ method: 'POST', url: '/v1/subjects/subject-demo-child/esdm-goals', headers: actor('user-professional-alpha', 'professional'), body: { codigoTecnicoDenver: 'CE_N1_I5' } });
  assert.equal(denied.status, 403);
  assert.equal(denied.body.error, 'SCOPE_DENIED');
});

test('troca de senha invalida refresh e exige credencial atual', async () => {
  const app = setup();
  const login = await app.handle({ method:'POST', url:'/v1/auth/login', body:{email:'profissional@fala-comigo.test',password:'DemoPassword-2026'} });
  assert.equal(login.status,200);
  const change = (currentPassword) => app.handle({ method:'POST',url:'/v1/auth/password',headers:{authorization:`Bearer ${login.body.accessToken}`},body:{currentPassword,password} });
  assert.equal((await change('wrong')).status,400);
  assert.equal((await change('DemoPassword-2026')).status,200);
  const renewed = await app.handle({method:'POST',url:'/v1/auth/refresh',body:{refreshToken:login.body.refreshToken}});
  assert.equal(renewed.status,401);
  assert.equal((await app.handle({method:'POST',url:'/v1/auth/login',body:{email:'profissional@fala-comigo.test',password}})).status,200);
});

test('PostgreSQL conserva ativação e permissões após reinício', {skip:!process.env.PGTEST_URL}, async () => {
  const store = createStore();
  const restarted = createStore();
  const email = `activation-${randomBytes(6).toString('hex')}@example.test`;
  let userId, invitationId;
  try {
    const app = createApp({store});
    const result = await invite(app,{email,scopes:['esdm_goal.read']});
    assert.equal(result.status,201); invitationId=result.body.id;
    userId=(await store.findRecord('invitations',{id:invitationId})).inviteeUserId;
    const active=await app.handle({method:'POST',url:'/v1/auth/activate',body:{token:result.body.token,password}});
    assert.equal(active.status,200);
    const second = createApp({store:restarted});
    const login=await second.handle({method:'POST',url:'/v1/auth/login',body:{email,password}});
    assert.equal(login.status,200);
    assert.ok(!login.body.scopes.includes('esdm_goal.write'));
    assert.equal((await second.handle({method:'POST',url:'/v1/auth/activate',body:{token:result.body.token,password}})).status,400);
  } finally {
    if(userId){
      await store.pool.query('delete from refresh_tokens where user_id=$1',[userId]);
      await store.pool.query('delete from activation_tokens where user_id=$1',[userId]);
      await store.pool.query('delete from memberships where user_id=$1',[userId]);
      await store.pool.query('delete from invitations where id=$1',[invitationId]);
      await store.pool.query('delete from audit_events where user_id=$1',[userId]);
      await store.pool.query('delete from users where id=$1',[userId]);
    }
    await store.pool.end();await restarted.pool.end();
  }
});

test('novo link invalida o anterior e permite ativar conta ainda pendente', async () => {
  const app=setup();const first=await invite(app);
  const renewed=await app.handle({method:'POST',url:`/v1/organizations/org-demo-alpha/account-invitations/${first.body.id}/reissue`,headers:actor()});
  assert.equal(renewed.status,201);
  const activate=(token)=>app.handle({method:'POST',url:'/v1/auth/activate',body:{token,password}});
  assert.equal((await activate(first.body.token)).status,400);
  assert.equal((await activate(renewed.body.token)).status,200);
});

test('chave clínica exige delegação explícita e remoção vale para JWT já emitido', async () => {
  const previous=process.env.MASTER_CRYPTO_KEY;
  process.env.MASTER_CRYPTO_KEY=randomBytes(32).toString('base64');
  const app=setup();
  try {
    await app.store.provisionOrganizationKey({organizationId:'org-demo-alpha',createdByUserId:'user-admin-alpha'});
    const member=app.store.memberships.find((entry)=>entry.id==='membership-professional-alpha');
    member.scopes=['organization.read','access.read','organization.key.read','school_collection.read'];
    const login=await app.handle({method:'POST',url:'/v1/auth/login',body:{email:'profissional@fala-comigo.test',password:'DemoPassword-2026'}});
    assert.equal(login.status,200);
    assert.ok(login.body.organizationKey);
    member.scopes=['organization.read','access.read'];
    const read=await app.handle({method:'GET',url:'/v1/organizations/org-demo-alpha/keys',headers:{authorization:`Bearer ${login.body.accessToken}`}});
    assert.equal(read.status,403);
  } finally {if(previous===undefined)delete process.env.MASTER_CRYPTO_KEY;else process.env.MASTER_CRYPTO_KEY=previous;}
});
