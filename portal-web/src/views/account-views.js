import { apiClient, clearSession } from '../api/client.js';
export const esc = (value) => String(value ?? '').replace(/[&<>"']/g, (char) => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[char]));
export function header(session) {
  return `<header class="topbar"><a class="brand" href="/clinica" data-route="/clinica">Fala Comigo <span>Portal</span></a><nav aria-label="Navegação principal"><a class="nav-link" href="/clinica" data-route="/clinica">Clínica</a><a class="nav-link" href="/escola" data-route="/escola">Escola</a><a class="nav-link" href="/relatorios" data-route="/relatorios">Relatórios</a><a class="nav-link" href="/pacientes" data-route="/pacientes">Pacientes e acessos</a>${session?.scopes?.includes('membership.read') ? '<a class="nav-link" href="/admin/profissionais" data-route="/admin/profissionais">Equipe</a>' : ''}<a class="nav-link" href="/conta" data-route="/conta">Minha conta</a></nav><button class="text-button" data-logout type="button">Sair</button></header>`;
}
export function renderActivateView() {
  return `<main class="auth-layout"><section class="auth-card"><p class="eyebrow">Convite pessoal</p><h1>Ativar sua conta</h1><p>Crie uma senha com pelo menos 16 caracteres. O convite vale por sete dias e pode ser usado uma vez.</p><form class="stack-form" data-activate><label for="activate-password">Nova senha</label><input id="activate-password" name="password" type="password" autocomplete="new-password" minlength="16" maxlength="72" required><label for="activate-confirm">Confirmar senha</label><input id="activate-confirm" name="confirm" type="password" autocomplete="new-password" minlength="16" maxlength="72" required><button class="primary-button" type="submit">Ativar conta</button><p role="status" data-status></p></form><a href="/login" data-route="/login">Ir para o login</a></section></main>`;
}
export function hydrateActivateView() {
  const token = new URLSearchParams(window.location.hash.slice(1)).get('token');
  window.history.replaceState({}, '', '/ativar');
  const form = document.querySelector('[data-activate]');
  const status = form.querySelector('[data-status]');
  if (!token) { status.textContent = 'Abra o link completo recebido da pessoa que enviou o convite.'; form.querySelector('button').disabled = true; return; }
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (form.elements.password.value !== form.elements.confirm.value) { status.textContent = 'As senhas precisam ser iguais.'; return; }
    const button = form.querySelector('button'); button.disabled = true;
    try {
      await apiClient.request('/v1/auth/activate', { method:'POST', body:{token, password:form.elements.password.value} });
      form.reset(); status.textContent = 'Conta ativada. Entre com seu email e senha.';
    } catch (_) { status.textContent = 'Não foi possível ativar. Verifique a senha e se o convite está válido e ainda não foi usado.'; button.disabled = false; }
  });
}
export function renderAccountView({ session }) {
  return `${header(session)}<main class="page-content"><h1>Minha conta</h1><section class="panel"><h2>Alterar senha</h2><form class="stack-form" data-password><label for="current-password">Senha atual</label><input id="current-password" name="currentPassword" type="password" autocomplete="current-password" required><label for="new-password">Nova senha (mínimo de 16 caracteres)</label><input id="new-password" name="password" type="password" autocomplete="new-password" minlength="16" maxlength="72" required><button class="primary-button" type="submit">Alterar e sair</button><p role="status" data-status></p></form><p class="notice">Após a alteração, entre novamente. As sessões anteriores deixam de ser renovadas.</p></section></main>`;
}
export function hydrateAccountView({ navigate }) {
  const form = document.querySelector('[data-password]');
  form.addEventListener('submit', async (event) => {
    event.preventDefault(); const button = form.querySelector('button'); button.disabled = true;
    try { await apiClient.request('/v1/auth/password', {method:'POST', body:{currentPassword:form.elements.currentPassword.value, password:form.elements.password.value}}); form.reset(); clearSession(); navigate('/login'); }
    catch (_) { form.querySelector('[data-status]').textContent = 'Confira a senha atual e use uma nova senha de 16 a 72 caracteres.'; button.disabled = false; }
  });
}
