export function renderAuthScreen() {
  return `
    <main class="auth-layout">
      <section class="auth-card" aria-labelledby="login-title">
        <p class="eyebrow">Cuidado Conectado</p>
        <h1 id="login-title">Entrar no portal profissional</h1>
        <p class="muted">Use os tokens emitidos pelo provedor de identidade do portal. O refresh token é rotacionado silenciosamente durante a sessão.</p>
        <form data-auth-form class="stack-form">
          <label for="access-token">Token de acesso JWT</label>
          <textarea id="access-token" name="token" rows="3" autocomplete="off" required></textarea>
          <label for="refresh-token">Refresh token</label>
          <textarea id="refresh-token" name="refreshToken" rows="2" autocomplete="off" required></textarea>
          <label for="user-id">Identidade do profissional</label>
          <input id="user-id" name="userId" value="user-professional-alpha" autocomplete="username" required />
          <label for="organization-id">Organização</label>
          <select id="organization-id" name="organizationId" required>
            <option value="org-demo-alpha">Clínica Aurora Demo</option>
            <option value="org-demo-beta">Escola Horizonte Demo</option>
          </select>
          <button class="primary-button" type="submit">Acessar ambiente autorizado</button>
        </form>
        <div class="notice" role="note">
          O portal envia o access token como <code>Authorization: Bearer</code> e troca o refresh token a cada renovação.
        </div>
      </section>
    </main>
  `;
}
