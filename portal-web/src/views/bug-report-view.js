import { apiClient } from '../api/client.js';

const escapeHtml = (value) => String(value).replace(/[&<>'"]/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[char]));
const sensitivePattern = /(prontu[áa]rio|diagn[óo]stico|laudo|cpf|rg\b|data de nascimento|nome completo|endere[cç]o|telefone|e-?mail|paciente\s*[:#]|subject[-_ ]?id|clinical|cl[íi]nic[ao])/iu;

export function renderBugReportView({ session }) {
  return `<div class="app-shell"><header class="topbar"><a class="brand" href="/clinica" data-route="/clinica">Fala Comigo <span>Portal</span></a><nav aria-label="Navegação principal"><a href="/clinica" data-route="/clinica" class="nav-link">Clínica</a><a href="/escola" data-route="/escola" class="nav-link">Escola</a><a href="/relatorios" data-route="/relatorios" class="nav-link">Relatórios</a><a href="/reportar-bug" data-route="/reportar-bug" class="nav-link selected">Reportar Bug</a></nav><div class="session-actions"><span class="session-id">${escapeHtml(session?.userId || '')}</span><button class="text-button" data-logout type="button">Sair</button></div></header><main class="page-content"><section class="panel" aria-labelledby="bug-report-title"><div class="page-heading"><div><p class="eyebrow">Feedback técnico restrito</p><h1 id="bug-report-title">Reportar Bug</h1><p class="muted">Envie apenas o comportamento técnico observado. Não inclua nomes, prontuários, diagnósticos, contatos ou identificadores de pacientes.</p></div></div><form class="stack-form" data-bug-report-form><label for="bug-severity">Tipo de feedback</label><select id="bug-severity" name="severity"><option value="leve">Leve</option><option value="travamento">Travamento</option><option value="sugestao">Sugestão</option></select><label for="bug-description">Descrição técnica</label><textarea id="bug-description" name="description" rows="7" maxlength="2000" required placeholder="Ex.: o botão Atualizar não responde depois de retornar da tela de escola."></textarea><p class="form-status" data-bug-report-status role="status"></p><div class="form-actions"><button class="primary-button" data-bug-report-submit type="submit">Enviar feedback</button><a class="secondary-button" href="/clinica" data-route="/clinica">Cancelar</a></div></form></section></main></div>`;
}

export function hydrateBugReportView() {
  const form = document.querySelector('[data-bug-report-form]');
  const descriptionInput = document.querySelector('[name="description"]');
  const severityInput = document.querySelector('[name="severity"]');
  const status = document.querySelector('[data-bug-report-status]');
  const submit = document.querySelector('[data-bug-report-submit]');
  form?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const description = String(descriptionInput?.value || '').trim();
    const severity = String(severityInput?.value || 'leve');
    if (!description || sensitivePattern.test(description)) {
      status.textContent = 'Remova dados pessoais ou clínicos. O reporte deve conter somente a falha técnica.';
      return;
    }
    submit.disabled = true;
    status.textContent = 'Enviando feedback técnico…';
    try {
      await apiClient.reportBug({ description, severity });
      status.textContent = 'Feedback enviado. Obrigado por ajudar no beta.';
      form.reset();
    } catch (error) {
      status.textContent = error.message === 'BUG_REPORT_PRIVACY_VIOLATION'
        ? 'O conteúdo contém dados que não podem ser enviados.'
        : 'Não foi possível enviar agora. Tente novamente quando houver conexão.';
    } finally {
      submit.disabled = false;
    }
  });
}
