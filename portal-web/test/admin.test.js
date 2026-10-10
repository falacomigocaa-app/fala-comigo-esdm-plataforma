import test from 'node:test';
import assert from 'node:assert/strict';
import {
  ADMIN_SCOPE_OPTIONS,
  hasAdministrativeScope,
  renderAdminProfessionalsView,
  renderMembers,
  scopesForMember
} from '../src/views/admin-professionals-view.js';

test('rota administrativa bloqueia sessão sem escopo de gestão', () => {
  const html = renderAdminProfessionalsView({
    session: { userId: 'user-professional', organizationId: 'org-demo-alpha', scopes: ['esdm_goal.read'] }
  });
  assert.equal(hasAdministrativeScope({ scopes: ['esdm_goal.read'] }), false);
  assert.match(html, /Acesso Negado/);
  assert.doesNotMatch(html, /data-admin-form/);
});

test('view administrativa renderiza controles de escopo e organização', () => {
  const html = renderAdminProfessionalsView({
    session: { userId: 'user-admin', organizationId: 'org-demo-alpha', scopes: ['membership.read'] }
  });
  assert.equal(hasAdministrativeScope({ scopes: ['membership.read'] }), true);
  assert.match(html, /Profissionais e escopos/);
  assert.match(html, /org-demo-alpha/);
  for (const scope of ADMIN_SCOPE_OPTIONS) assert.match(html, new RegExp(scope.value.replace('.', '\\.'), 'u'));
  assert.equal((html.match(/name="scopes"/g) || []).length, ADMIN_SCOPE_OPTIONS.length);
});

test('tabela administrativa lista escopos explícitos e aplica fallback por perfil', () => {
  const explicit = scopesForMember({ role: 'professional', scopes: ['report.read'] });
  assert.deepEqual(explicit, ['report.read']);
  const html = renderMembers([
    { id: 'membership-1', userId: 'user-professional', role: 'professional', status: 'active', scopes: ['esdm_goal.write', 'report.read'] },
    { id: 'membership-2', userId: 'user-caregiver', role: 'caregiver', status: 'active' }
  ]);
  assert.match(html, /user-professional/);
  assert.match(html, /esdm_goal\.write/);
  assert.match(html, /report\.read/);
  assert.match(html, /user-caregiver/);
  assert.match(html, /Editar acesso/);
  assert.match(renderMembers([]), /Nenhum profissional vinculado/);
});

test('APIClient administrativo usa Bearer para listar e convidar profissional', async () => {
  const requests = [];
  globalThis.window = {
    PORTAL_API_BASE: 'http://127.0.0.1:8787',
    localStorage: {
      getItem: () => JSON.stringify({ token: 'admin-token' }),
      setItem: () => {},
      removeItem: () => {}
    }
  };
  globalThis.fetch = async (url, options) => {
    requests.push({ url, options });
    return {
      ok: true,
      status: url.endsWith('/memberships') ? 200 : 201,
      async json() { return url.endsWith('/memberships') ? { memberships: [] } : { invitation: { id: 'invite-1' } }; }
    };
  };
  const { APIClient } = await import(`../src/api/client.js?admin=${Date.now()}`);
  const client = new APIClient();
  await client.carregarProfissionais('org/demo');
  await client.convidarProfissional('org/demo', {
    inviteeUserId: 'user-new',
    role: 'professional',
    scopes: ['esdm_goal.write'],
    purpose: 'Acesso profissional ao portal'
  });

  assert.equal(requests[0].url, 'http://127.0.0.1:8787/v1/organizations/org%2Fdemo/memberships');
  assert.equal(requests[1].url, 'http://127.0.0.1:8787/v1/organizations/org%2Fdemo/invitations');
  assert.equal(requests[1].options.headers.authorization, 'Bearer admin-token');
  assert.deepEqual(JSON.parse(requests[1].options.body), {
    inviteeUserId: 'user-new',
    role: 'professional',
    scopes: ['esdm_goal.write'],
    purpose: 'Acesso profissional ao portal'
  });
});

test('empty explicit membership scopes stay empty in the admin table', async () => {
  const { scopesForMember } = await import('../src/views/admin-professionals-view.js');
  assert.deepEqual(scopesForMember({ role: 'professional', scopes: [] }), []);
});
