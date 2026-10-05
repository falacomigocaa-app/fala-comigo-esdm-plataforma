export function renderAuthScreen() {
  return `
    <main class="auth-layout">
      <section class="auth-card" aria-labelledby="login-title">
        <p class="eyebrow">Cuidado Conectado</p>
        <h1 id="login-title">Entrar no portal profissional</h1>
        <p class="muted">Ambiente local de validação com identidade sintética. Nenhuma senha ou dado real é solicitado.</p>
        <form data-auth-form class="stack-form">
          <label for="user-id">Identidade sintética</label>
          <input id="user-id" name="userId" value="user-professional-alpha" autocomplete="off" required />
          <label for="organization-id">Organização</label>
          <select id="organization-id" name="organizationId" required>
            <option value="org-demo-alpha">Clínica Aurora Demo</option>
            <option value="org-demo-beta">Escola Horizonte Demo</option>
          </select>
          <p class="field-hint">Ex.: <code>user-professional-alpha</code> ou <code>user-admin-beta</code></p>
          <button class="primary-button" type="submit">Acessar ambiente de teste</button>
        </form>
        <div class="notice" role="note">
          O cabeçalho <code>x-synthetic-user-id</code> será enviado somente para a API local de desenvolvimento.
        </div>
      </section>
    </main>
  `;
}
