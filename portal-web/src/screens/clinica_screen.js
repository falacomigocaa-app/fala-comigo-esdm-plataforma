import { apiClient, goalTranslations } from '../api/client.js';

const escapeHtml = (value) => String(value).replace(/[&<>'"]/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[char]));

function renderHeader(title, session) {
  return `<header class="topbar"><a class="brand" href="/clinica" data-route="/clinica">Fala Comigo <span>Portal</span></a><nav aria-label="Navegação principal"><a href="/clinica" data-route="/clinica" class="nav-link ${title.includes('Clínica') ? 'selected' : ''}">Clínica</a><a href="/escola" data-route="/escola" class="nav-link ${title.includes('Escola') ? 'selected' : ''}">Escola</a><a href="/relatorios" data-route="/relatorios" class="nav-link">Relatórios</a><a href="/admin/profissionais" data-route="/admin/profissionais" class="nav-link">Profissionais</a><a href="/pacientes" data-route="/pacientes" class="nav-link">Pacientes e acessos</a><a href="/conta" data-route="/conta" class="nav-link">Minha conta</a></nav><div class="session-actions"><span class="session-id">${escapeHtml(session?.userId || '')}</span><button class="text-button" data-logout type="button">Sair</button></div></header>`;
}

export function renderClinicaScreen({ session }) {
  return `
    <div class="app-shell">
      ${renderHeader('Painel da Clínica', session)}
      <main class="page-content">
        <div class="page-heading"><div><p class="eyebrow">Especialista autorizado</p><h1>Metas de desenvolvimento</h1><p class="muted">Acompanhe os pacientes que autorizaram o acesso da sua equipe.</p></div><span class="badge active">Área clínica</span></div>
        <section class="panel" aria-labelledby="patients-title">
          <div class="section-heading"><div><p class="eyebrow">Acesso concedido</p><h2 id="patients-title">Pacientes autorizados</h2></div><span class="form-status" data-clinic-status>Carregando pacientes…</span></div>
          <div class="table-wrap"><table><thead><tr><th>Paciente</th><th>Organização</th><th>Vínculo</th><th>Validade</th></tr></thead><tbody data-patients-body><tr><td colspan="4">Carregando…</td></tr></tbody></table></div>
        </section>
        <section class="two-column">
          <div class="panel"><div class="section-heading"><div><p class="eyebrow">Plano de acompanhamento</p><h2>Registrar nova meta</h2></div></div><form data-goal-form class="stack-form"><label for="patient-id">Paciente</label><select id="patient-id" name="patientId" data-patient-select disabled><option>Carregando…</option></select><label for="goal-code">Código técnico Denver</label><select id="goal-code" name="goalCode" data-goal-code>${Object.keys(goalTranslations).map((code) => `<option value="${code}">${code}</option>`).join('')}</select><div class="translation-preview" data-goal-preview></div><button class="primary-button" data-save-goal type="submit" disabled>Salvar meta autorizada</button><p class="form-status" data-goal-form-status>Selecione um paciente autorizado.</p></form></div>
          <div class="panel"><div class="section-heading"><div><p class="eyebrow">Acompanhamento</p><h2>Metas cadastradas</h2></div></div><div class="table-wrap"><table><thead><tr><th>Código</th><th>Missão para a família</th><th>Status</th><th>Origem</th></tr></thead><tbody data-goals-body><tr><td colspan="4">Selecione um paciente para carregar as metas.</td></tr></tbody></table></div></div>
        </section>
      </main>
    </div>
  `;
}

export async function hydrateClinicaScreen({ session }) {
  const status = document.querySelector('[data-clinic-status]');
  const patientBody = document.querySelector('[data-patients-body]');
  const patientSelect = document.querySelector('[data-patient-select]');
  const goalsBody = document.querySelector('[data-goals-body]');
  const form = document.querySelector('[data-goal-form]');
  const codeSelect = document.querySelector('[data-goal-code]');
  const preview = document.querySelector('[data-goal-preview]');
  const saveButton = document.querySelector('[data-save-goal]');
  const formStatus = document.querySelector('[data-goal-form-status]');
  if (!status || !patientBody || !patientSelect || !goalsBody || !form) return;

  const updatePreview = () => {
    const translation = goalTranslations[codeSelect.value];
    preview.innerHTML = `<strong>${escapeHtml(translation.missaoPais)}</strong><span>${escapeHtml(translation.dicaPratica)}</span>`;
  };
  const renderGoals = (goals) => {
    goalsBody.innerHTML = goals.length ? goals.map((goal) => `<tr><td><code>${escapeHtml(goal.codigoTecnicoDenver)}</code></td><td>${escapeHtml(goal.missaoPais)}</td><td>${escapeHtml(goal.status)}</td><td><span class="badge active">Sincronizada</span></td></tr>`).join('') : '<tr><td colspan="4">Nenhuma meta ativa.</td></tr>';
  };
  let loadGeneration = 0;
  const loadGoals = async (subjectId) => {
    const generation = ++loadGeneration;
    goalsBody.innerHTML = '<tr><td colspan="4">Carregando metas…</td></tr>';
    const result = await apiClient.carregarMetas(subjectId);
    if (generation === loadGeneration) renderGoals(result.goals || []);
  };

  updatePreview();
  codeSelect.addEventListener('change', updatePreview);
  status.textContent = 'Consultando autorizações…';
  const result = await apiClient.carregarPacientes(session.organizationId);
  const patients = result.subjects || [];
  if (!patients.length) {
    patientBody.innerHTML = '<tr><td colspan="4">Nenhum paciente autorizado para esta organização.</td></tr>';
    status.textContent = 'Nenhum vínculo vigente.';
    return;
  }
  patientBody.innerHTML = patients.map((patient) => `<tr><td><strong>${escapeHtml(patient.displayName)}</strong><small>${escapeHtml(patient.id)}</small></td><td>${escapeHtml(session.organizationId)}</td><td><span class="badge active">autorizado</span></td><td>validado pela API</td></tr>`).join('');
  patientSelect.innerHTML = patients.map((patient) => `<option value="${escapeHtml(patient.id)}">${escapeHtml(patient.displayName)}</option>`).join('');
  patientSelect.disabled = false;
  saveButton.disabled = !session.scopes?.includes('esdm_goal.write');
  status.textContent = `${patients.length} paciente(s) autorizado(s).`;
  await loadGoals(patientSelect.value);

  patientSelect.addEventListener('change', () => loadGoals(patientSelect.value).catch((error) => { goalsBody.innerHTML = `<tr><td colspan="4">Falha: ${escapeHtml(error.message)}</td></tr>`; }));
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    saveButton.disabled = true;
    formStatus.textContent = 'Salvando meta…';
    const code = codeSelect.value;
    try {
      await apiClient.salvarMeta(patientSelect.value, { codigoTecnicoDenver: code, status: 'Em Progresso', passoAtualAba: 1 });
      await loadGoals(patientSelect.value);
      formStatus.textContent = 'Meta salva.';
    } catch (error) {
      formStatus.textContent = `Não foi possível salvar: ${error.message}`;
    } finally {
      saveButton.disabled = !session.scopes?.includes('esdm_goal.write');
    }
  });
}
