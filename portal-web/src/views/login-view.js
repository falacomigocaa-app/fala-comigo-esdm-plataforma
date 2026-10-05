import { apiClient, saveSession } from '../api/client.js';

export function renderLoginView() {
  return `
    <main class="auth-layout">
      <section class="auth-card" aria-labelledby="central-login-title">
        <p class="eyebrow">Portal Cuidado Conectado</p>
        <h1 id="central-login-title">Entrar com sua conta</h1>
        <p class="muted">Acesse metas, coletas e relatórios com uma sessão protegida.</p>
        <form class="stack-form" data-login-form>
          <label for="login-email">Email profissional</label>
          <input id="login-email" name="email" type="email" autocomplete="username" required />
          <label for="login-password">Senha</label>
          <input id="login-password" name="password" type="password" autocomplete="current-password" required />
          <p class="form-status" data-login-status role="status"></p>
          <button class="primary-button" data-login-submit type="submit">Entrar</button>
        </form>
        <p class="notice">Sua sessão usa access token de curta duração e renovação segura por refresh token rotativo.</p>
      </section>
    </main>
  `;
}

export function hydrateLoginView({ navigate }) {
  const form = document.querySelector('[data-login-form]');
  const status = document.querySelector('[data-login-status]');
  const submit = document.querySelector('[data-login-submit]');
  form?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const data = new FormData(form);
    submit.disabled = true;
    submit.textContent = 'Entrando…';
    status.textContent = 'Validando credenciais…';
    try {
      const payload = await apiClient.login(
        String(data.get('email') || '').trim(),
        String(data.get('password') || '')
      );
      if (typeof payload.accessToken !== 'string' || typeof payload.refreshToken !== 'string') {
        throw new Error('Resposta de autenticação incompleta.');
      }
      saveSession({
        token: payload.accessToken,
        refreshToken: payload.refreshToken,
        userId: payload.userId,
        organizationId: payload.organizationId,
        scopes: payload.scopes
      });
      navigate('/clinica');
    } catch (error) {
      status.textContent = error.status === 401
        ? 'Email ou senha inválidos.'
        : 'Não foi possível conectar ao Portal. Tente novamente.';
      submit.disabled = false;
      submit.textContent = 'Entrar';
    }
  });
}
