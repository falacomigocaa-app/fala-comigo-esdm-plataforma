import { apiClient, saveSession } from '../api/client.js';
import { setBetaBypass } from '../services/beta-gate.js';

const escapeHtml = (value) => String(value ?? '').replace(/[&<>'"]/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[char]));

export function renderInvitationView() {
  return `<main class="auth-layout"><section class="auth-card" aria-labelledby="invitation-title"><p class="eyebrow">Convite seguro</p><h1 id="invitation-title">Você foi convidado para o Fala Comigo</h1><div data-invitation-content><p class="form-status">Carregando convite…</p></div></section></main>`;
}

export async function hydrateInvitationView() {
  const root = document.querySelector('[data-invitation-content]');
  if (!root) return;
  const token = decodeURIComponent(window.location.pathname.split('/convite/')[1] || '').trim();
  if (!token) { root.innerHTML = '<p class="form-status">Link de convite inválido.</p>'; return; }
  try {
    const invitation = await apiClient.previewInvitation(token);
    root.innerHTML = `<div class="notice"><strong>Organização:</strong> ${escapeHtml(invitation.organizationId)}<br><strong>Perfil:</strong> ${escapeHtml(invitation.role)}<br><strong>Validade:</strong> ${escapeHtml(new Date(invitation.expiresAt).toLocaleDateString('pt-BR'))}</div><p class="muted">Crie sua conta para aceitar o convite. A senha será usada somente para sua própria conta.</p><form class="stack-form" data-invitation-form><label for="invitation-email">Seu e-mail</label><input id="invitation-email" name="email" type="email" value="${escapeHtml(invitation.inviteeEmail || '')}" required><label for="invitation-password">Crie uma senha</label><input id="invitation-password" name="password" type="password" minlength="8" autocomplete="new-password" required><p class="form-status" data-invitation-status role="status"></p><button class="primary-button" type="submit">Criar conta e aceitar convite</button></form>`;
    const form = root.querySelector('[data-invitation-form]');
    const status = root.querySelector('[data-invitation-status]');
    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      const data = new FormData(form);
      const button = form.querySelector('button');
      button.disabled = true;
      status.textContent = 'Criando sua conta e ativando o acesso…';
      try {
        const payload = await apiClient.registerInvitation({ invitationToken: token, email: String(data.get('email') || '').trim(), password: String(data.get('password') || '') });
        saveSession({ token: payload.accessToken, refreshToken: payload.refreshToken, userId: payload.userId, organizationId: payload.organizationId, scopes: payload.scopes, betaBypass: payload.betaBypass === true });
        setBetaBypass(payload.betaBypass === true);
        status.textContent = 'Acesso ativado. Redirecionando…';
        window.location.href = './portal/';
      } catch (error) {
        status.textContent = error.message === 'ACCOUNT_EXISTS_USE_LOGIN' ? 'Esta conta já existe. Entre no Portal com sua senha para continuar.' : 'Não foi possível aceitar o convite. Verifique os dados e tente novamente.';
        button.disabled = false;
      }
    });
  } catch (_) {
    root.innerHTML = '<p class="form-status">Este convite é inválido, expirou ou já foi utilizado.</p><a class="secondary-button" href="./portal/">Abrir Portal</a>';
  }
}
