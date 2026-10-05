import { apiClient } from '../api/client.js';

export const ADMIN_SCOPE_OPTIONS = [
  { value: 'esdm_goal.read', label: 'Metas: leitura' },
  { value: 'esdm_goal.write', label: 'Metas: escrita' },
  { value: 'school_collection.read', label: 'Coletas: leitura' },
  { value: 'school_collection.write', label: 'Coletas: escrita' },
  { value: 'report.read', label: 'Relatórios: leitura' }
];

const ROLE_SCOPES = {
  owner: ADMIN_SCOPE_OPTIONS.map((scope) => scope.value),
  org_admin: ADMIN_SCOPE_OPTIONS.map((scope) => scope.value),
  professional: ['esdm_goal.read', 'esdm_goal.write'],
  caregiver: ['report.read']
};

const escapeHtml = (value) => String(value ?? '').replace(/[&<>'"]/g, (char) => ({
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  "'": '&#39;',
  '"': '&quot;'
}[char]));

export function hasAdministrativeScope(session) {
  const scopes = Array.isArray(session?.scopes) ? session.scopes : [];
  return scopes.includes('membership.read') || scopes.includes('access.invite');
}

export function scopesForMember(member) {
  return Array.isArray(member?.scopes) && member.scopes.length
    ? member.scopes
    : (ROLE_SCOPES[member?.role] || []);
}

function renderHeader(session) {
  return `<header class="topbar"><a class="brand" href="/admin/profissionais" data-route="/admin/profissionais">Fala Comigo <span>Portal</span></a><nav aria-label="Navegação principal"><a href="/clinica" data-route="/clinica" class="nav-link">Clínica</a><a href="/escola" data-route="/escola" class="nav-link">Escola</a><a href="/relatorios" data-route="/relatorios" class="nav-link">Relatórios</a><a href="/admin/profissionais" data-route="/admin/profissionais" class="nav-link selected">Administração</a></nav><div class="session-actions"><span class="session-id">${escapeHtml(session?.userId || '')}</span><button class="text-button" data-logout type="button">Sair</button></div></header>`;
}

function renderDenied({ session }) {
  return `<div class="app-shell"><header class="topbar"><a class="brand" href="/clinica">Fala Comigo <span>Portal</span></a><div class="session-actions"><span class="session-id">${escapeHtml(session?.userId || '')}</span></div></header><main class="page-content"><section class="panel access-denied" role="alert"><p class="eyebrow">Área restrita</p><h1>Acesso Negado</h1><p>Seu perfil não possui escopo administrativo para gerenciar profissionais desta organização.</p><a class="secondary-button" href="/clinica">Voltar ao painel clínico</a></section></main></div>`;
}

export function renderAdminProfessionalsView({ session }) {
  if (!hasAdministrativeScope(session)) return renderDenied({ session });
  const scopeControls = ADMIN_SCOPE_OPTIONS.map((scope) => `<label class="scope-option"><input type="checkbox" name="scopes" value="${scope.value}"><span>${scope.label}</span></label>`).join('');
  return `<div class="app-shell admin-page">${renderHeader(session)}<main class="page-content">
    <div class="page-heading"><div><p class="eyebrow">Controle de acesso</p><h1>Profissionais e escopos</h1><p class="muted">Administre os vínculos da organização e defina o mínimo de acesso necessário para cada profissional.</p></div><span class="badge active">Organização: ${escapeHtml(session?.organizationId || '—')}</span></div>
    <section class="panel"><div class="section-heading"><div><p class="eyebrow">Memberships</p><h2>Profissionais vinculados</h2></div><span class="form-status" data-admin-status>Carregando profissionais…</span></div><div class="table-wrap"><table><thead><tr><th>Profissional</th><th>Perfil</th><th>Escopos concedidos</th><th>Status</th><th>Ação</th></tr></thead><tbody data-admin-members><tr><td colspan="5">Carregando…</td></tr></tbody></table></div></section>
    <section class="panel admin-form-panel"><div class="section-heading"><div><p class="eyebrow">Convite e edição</p><h2 data-admin-form-title>Adicionar profissional</h2></div><span class="form-status">Os escopos serão enviados ao portal-api.</span></div><form class="stack-form" data-admin-form><label for="admin-user-id">ID do profissional</label><input id="admin-user-id" name="inviteeUserId" placeholder="user-professional-..." required><label for="admin-role">Perfil organizacional</label><select id="admin-role" name="role"><option value="professional">Profissional</option><option value="org_admin">Administrador</option><option value="caregiver">Cuidador</option></select><fieldset class="scope-fieldset"><legend>Escopos de acesso</legend><div class="scope-grid">${scopeControls}</div></fieldset><div class="admin-form-actions"><button class="primary-button" data-admin-submit type="submit">Salvar profissional</button><button class="secondary-button" data-admin-cancel type="button" hidden>Cancelar edição</button></div><p class="form-status" data-admin-form-status>Escolha apenas os escopos necessários à função.</p></form></section>
  </main></div>`;
}

export function renderMembers(members) {
  if (!members.length) return '<tr><td colspan="5">Nenhum profissional vinculado a esta organização.</td></tr>';
  return members.map((member) => {
    const scopes = scopesForMember(member);
    const scopeBadges = scopes.length ? scopes.map((scope) => `<span class="scope-badge">${escapeHtml(scope)}</span>`).join('') : '<span class="muted">Nenhum escopo</span>';
    return `<tr><td><strong>${escapeHtml(member.userId)}</strong><small>${escapeHtml(member.id)}</small></td><td>${escapeHtml(member.role)}</td><td><div class="scope-badges">${scopeBadges}</div></td><td><span class="badge ${member.status === 'active' ? 'active' : 'local'}">${escapeHtml(member.status || 'pendente')}</span></td><td><button class="text-button" data-edit-professional="${escapeHtml(member.userId)}" type="button">Editar acesso</button></td></tr>`;
  }).join('');
}

export async function hydrateAdminProfessionalsView({ session }) {
  if (!hasAdministrativeScope(session)) return;
  const status = document.querySelector('[data-admin-status]');
  const membersBody = document.querySelector('[data-admin-members]');
  const form = document.querySelector('[data-admin-form]');
  const formStatus = document.querySelector('[data-admin-form-status]');
  const formTitle = document.querySelector('[data-admin-form-title]');
  const submit = document.querySelector('[data-admin-submit]');
  const cancel = document.querySelector('[data-admin-cancel]');
  if (!status || !membersBody || !form) return;

  let members = [];
  const resetForm = () => {
    form.reset();
    formTitle.textContent = 'Adicionar profissional';
    submit.textContent = 'Salvar profissional';
    cancel.hidden = true;
    formStatus.textContent = 'Escolha apenas os escopos necessários à função.';
  };
  const loadMembers = async () => {
    status.textContent = 'Carregando profissionais…';
    membersBody.innerHTML = '<tr><td colspan="5">Carregando…</td></tr>';
    try {
      const result = await apiClient.carregarProfissionais(session.organizationId);
      members = result.memberships || [];
      membersBody.innerHTML = renderMembers(members);
      status.textContent = `${members.length} vínculo(s) encontrado(s).`;
      membersBody.querySelectorAll('[data-edit-professional]').forEach((button) => {
        button.addEventListener('click', () => {
          const member = members.find((candidate) => candidate.userId === button.dataset.editProfessional);
          if (!member) return;
          form.elements.inviteeUserId.value = member.userId;
          form.elements.role.value = member.role === 'owner' ? 'org_admin' : member.role;
          form.querySelectorAll('input[name="scopes"]').forEach((input) => {
            input.checked = scopesForMember(member).includes(input.value);
          });
          formTitle.textContent = 'Editar acesso profissional';
          submit.textContent = 'Reenviar convite com escopos';
          cancel.hidden = false;
          formStatus.textContent = 'Revise os escopos e confirme para enviar uma nova configuração de acesso.';
        });
      });
    } catch (error) {
      status.textContent = `Falha ao carregar: ${error.message}`;
      membersBody.innerHTML = '<tr><td colspan="5">Não foi possível carregar os profissionais.</td></tr>';
    }
  };

  cancel.addEventListener('click', resetForm);
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    submit.disabled = true;
    formStatus.textContent = 'Salvando escopos e enviando convite…';
    const formData = new FormData(form);
    const scopes = formData.getAll('scopes');
    try {
      await apiClient.convidarProfissional(session.organizationId, {
        inviteeUserId: formData.get('inviteeUserId'),
        role: formData.get('role'),
        scopes,
        purpose: 'Acesso profissional ao portal'
      });
      resetForm();
      formStatus.textContent = 'Profissional salvo. A lista foi atualizada.';
      await loadMembers();
    } catch (error) {
      formStatus.textContent = `Não foi possível salvar: ${error.message}`;
    } finally {
      submit.disabled = false;
    }
  });

  await loadMembers();
}
