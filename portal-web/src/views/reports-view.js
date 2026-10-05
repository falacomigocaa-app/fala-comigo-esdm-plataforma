import { apiClient } from '../api/client.js';

const levels = { Recusa: 0, 'Ajuda Física': 1, 'Ajuda Verbal': 2, Independente: 3 };
const periodOptions = [
  { value: '7', label: 'Últimos 7 dias' },
  { value: '30', label: 'Últimos 30 dias' },
  { value: 'all', label: 'Todo o histórico' }
];

const escapeHtml = (value) => String(value ?? '').replace(/[&<>'"]/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[char]));

function renderHeader(session) {
  return `<header class="topbar"><a class="brand" href="/relatorios" data-route="/relatorios">Fala Comigo <span>Portal</span></a><nav aria-label="Navegação principal"><a href="/clinica" data-route="/clinica" class="nav-link">Clínica</a><a href="/escola" data-route="/escola" class="nav-link">Escola</a><a href="/relatorios" data-route="/relatorios" class="nav-link selected">Relatórios</a></nav><div class="session-actions"><span class="session-id">${escapeHtml(session?.userId || '')}</span><button class="text-button" data-logout type="button">Sair</button></div></header>`;
}

export function renderReportsView({ session }) {
  return `<div class="app-shell report-page">${renderHeader(session)}<main class="page-content">
    <div class="page-heading"><div><p class="eyebrow">Compilado clínico</p><h1>Relatórios de evolução</h1><p class="muted">Leitura temporal das coletas escolares e das metas ESDM/ABA autorizadas.</p></div><div class="report-actions"><button class="secondary-button" data-refresh-report type="button">Atualizar dados</button><button class="primary-button" data-print-report type="button">Imprimir relatório</button></div></div>
    <section class="panel report-filters" aria-labelledby="report-filters-title"><div class="section-heading"><div><p class="eyebrow">Filtros de análise</p><h2 id="report-filters-title">Escolha o recorte do paciente</h2></div><span class="form-status" data-report-status>Carregando dados autorizados…</span></div><div class="report-filter-grid"><label>Paciente<select data-report-subject disabled><option>Carregando pacientes…</option></select></label><label>Período<select data-report-period>${periodOptions.map((option) => `<option value="${option.value}"${option.value === '30' ? ' selected' : ''}>${option.label}</option>`).join('')}</select></label><label>Tipo de meta<select data-report-goal-filter disabled><option value="all">Todas as metas</option></select></label></div></section>
    <section class="report-summary-grid" aria-label="Indicadores do relatório"><article class="report-metric"><span>Coletas no período</span><strong data-report-collection-count>—</strong><small>registros escolares</small></article><article class="report-metric"><span>Autonomia média</span><strong data-report-average>—</strong><small>de 3 pontos</small></article><article class="report-metric"><span>Metas acompanhadas</span><strong data-report-goal-count>—</strong><small>metas ativas</small></article><article class="report-metric"><span>Último registro</span><strong data-report-last-date>—</strong><small>data da coleta</small></article></section>
    <section class="panel report-chart-panel"><div class="section-heading"><div><p class="eyebrow">Evolução temporal</p><h2>Autonomia observada nas coletas</h2></div><span class="chart-legend"><i></i> Pontuação de autonomia</span></div><div class="report-chart-wrap" data-report-chart aria-live="polite"><p class="report-empty">Carregando gráfico…</p></div></section>
    <section class="panel report-goals-panel"><div class="section-heading"><div><p class="eyebrow">ESDM / ABA</p><h2>Metas do paciente</h2></div></div><div class="table-wrap"><table><thead><tr><th>Código</th><th>Missão para a família</th><th>Status</th><th>Atualização</th></tr></thead><tbody data-report-goals><tr><td colspan="4">Carregando metas…</td></tr></tbody></table></div></section>
    <section class="panel report-summary-panel" data-report-print-summary><div class="section-heading"><div><p class="eyebrow">Sumário individual</p><h2>Leitura para discussão clínica</h2></div></div><p class="muted" data-report-summary>O sumário será preenchido após a seleção do paciente.</p></section>
  </main></div>`;
}

export function filterReportData(collections, goals, { period = '30', goalCode = 'all', now = new Date() } = {}) {
  const cutoff = period === 'all' ? null : new Date(now.getTime() - Number(period) * 24 * 60 * 60 * 1000);
  const filteredCollections = collections.filter((item) => {
    const date = new Date(item.dataRegistro);
    return !Number.isNaN(date.getTime()) && (!cutoff || date >= cutoff);
  }).sort((left, right) => new Date(left.dataRegistro) - new Date(right.dataRegistro));
  const filteredGoals = goals.filter((goal) => goalCode === 'all' || goal.codigoTecnicoDenver === goalCode);
  return { collections: filteredCollections, goals: filteredGoals };
}

export function summarizeReport(collections, goals) {
  const scores = collections.map((item) => levels[item.nivelSuporte]).filter((score) => Number.isFinite(score));
  const average = scores.length ? scores.reduce((sum, score) => sum + score, 0) / scores.length : null;
  const last = collections.at(-1);
  return {
    collectionCount: collections.length,
    average,
    goalCount: goals.length,
    lastDate: last ? new Date(last.dataRegistro) : null
  };
}

function renderChart(collections) {
  if (!collections.length) return '<div class="report-empty"><strong>Nenhuma coleta realizada no período.</strong><span>Amplie o período ou selecione outro paciente para visualizar a evolução.</span></div>';
  const width = 900;
  const height = 300;
  const padding = { top: 24, right: 24, bottom: 46, left: 48 };
  const plotWidth = width - padding.left - padding.right;
  const plotHeight = height - padding.top - padding.bottom;
  const points = collections.map((item, index) => {
    const x = padding.left + (collections.length === 1 ? plotWidth / 2 : (index / (collections.length - 1)) * plotWidth);
    const y = padding.top + plotHeight - ((levels[item.nivelSuporte] ?? 0) / 3) * plotHeight;
    return { x, y, score: levels[item.nivelSuporte] ?? 0, date: new Date(item.dataRegistro) };
  });
  const line = points.map((point) => `${point.x},${point.y}`).join(' ');
  const grid = [0, 1, 2, 3].map((score) => {
    const y = padding.top + plotHeight - (score / 3) * plotHeight;
    return `<line x1="${padding.left}" y1="${y}" x2="${width - padding.right}" y2="${y}" class="chart-grid"/><text x="${padding.left - 12}" y="${y + 4}" text-anchor="end" class="chart-label">${score}</text>`;
  }).join('');
  const dots = points.map((point) => `<circle cx="${point.x}" cy="${point.y}" r="5" class="chart-dot"><title>${point.date.toLocaleDateString('pt-BR')} · ${point.score}/3</title></circle>`).join('');
  const firstDate = points[0].date.toLocaleDateString('pt-BR');
  const lastDate = points.at(-1).date.toLocaleDateString('pt-BR');
  return `<svg class="report-chart" viewBox="0 0 ${width} ${height}" role="img" aria-label="Evolução da autonomia de 0 a 3 pontos"><g>${grid}</g><polyline points="${line}" class="chart-line" fill="none"/>${dots}<text x="${padding.left}" y="${height - 14}" class="chart-label">${firstDate}</text><text x="${width - padding.right}" y="${height - 14}" text-anchor="end" class="chart-label">${lastDate}</text></svg>`;
}

function renderGoals(goals) {
  if (!goals.length) return '<tr><td colspan="4">Nenhuma meta corresponde ao filtro escolhido.</td></tr>';
  return goals.map((goal) => `<tr><td><code>${escapeHtml(goal.codigoTecnicoDenver)}</code></td><td>${escapeHtml(goal.missaoPais || '—')}</td><td><span class="badge ${goal.status === 'Adquirido' ? 'active' : 'local'}">${escapeHtml(goal.status || 'Sem status')}</span></td><td>${goal.updatedAt ? new Date(goal.updatedAt).toLocaleDateString('pt-BR') : '—'}</td></tr>`).join('');
}

export async function hydrateReportsView({ session }) {
  const status = document.querySelector('[data-report-status]');
  const subjectSelect = document.querySelector('[data-report-subject]');
  const periodSelect = document.querySelector('[data-report-period]');
  const goalFilter = document.querySelector('[data-report-goal-filter]');
  const chart = document.querySelector('[data-report-chart]');
  const goalsBody = document.querySelector('[data-report-goals]');
  if (!status || !subjectSelect || !periodSelect || !goalFilter || !chart || !goalsBody) return;

  let collections = [];
  let goals = [];
  let currentSubjectId = session?.subjectId || '';
  const metricNodes = {
    collectionCount: document.querySelector('[data-report-collection-count]'),
    average: document.querySelector('[data-report-average]'),
    goalCount: document.querySelector('[data-report-goal-count]'),
    lastDate: document.querySelector('[data-report-last-date]'),
    summary: document.querySelector('[data-report-summary]')
  };

  const render = () => {
    const filtered = filterReportData(collections, goals, { period: periodSelect.value, goalCode: goalFilter.value });
    const summary = summarizeReport(filtered.collections, filtered.goals);
    chart.innerHTML = renderChart(filtered.collections);
    goalsBody.innerHTML = renderGoals(filtered.goals);
    metricNodes.collectionCount.textContent = summary.collectionCount;
    metricNodes.average.textContent = summary.average === null ? '—' : summary.average.toFixed(1);
    metricNodes.goalCount.textContent = summary.goalCount;
    metricNodes.lastDate.textContent = summary.lastDate ? summary.lastDate.toLocaleDateString('pt-BR') : '—';
    metricNodes.summary.textContent = summary.collectionCount
      ? `Foram observadas ${summary.collectionCount} coleta(s), com autonomia média de ${summary.average.toFixed(1)} de 3 no período selecionado. ${summary.goalCount} meta(s) permanecem no recorte para discussão com a equipe.`
      : 'Nenhuma coleta realizada no período selecionado. O histórico permanece protegido e poderá ser consultado após novo registro autorizado.';
  };

  const loadSubject = async (subjectId) => {
    currentSubjectId = subjectId;
    status.textContent = 'Carregando coletas e metas autorizadas…';
    chart.innerHTML = '<p class="report-empty">Carregando gráfico…</p>';
    const [collectionResult, goalResult] = await Promise.all([
      apiClient.carregarHistoricoEscolar(subjectId),
      apiClient.carregarMetas(subjectId)
    ]);
    collections = collectionResult.collections || [];
    goals = goalResult.goals || [];
    goalFilter.innerHTML = `<option value="all">Todas as metas</option>${goals.map((goal) => `<option value="${escapeHtml(goal.codigoTecnicoDenver)}">${escapeHtml(goal.codigoTecnicoDenver)}</option>`).join('')}`;
    goalFilter.disabled = false;
    render();
    status.textContent = `${collections.length} coleta(s) e ${goals.length} meta(s) carregada(s).`;
  };

  try {
    const patientsResult = await apiClient.carregarPacientes(session?.organizationId || 'org-demo-alpha');
    const patients = patientsResult.subjects || [];
    if (!patients.length) {
      status.textContent = 'Nenhum paciente autorizado.';
      subjectSelect.innerHTML = '<option>Sem pacientes autorizados</option>';
      return;
    }
    subjectSelect.innerHTML = patients.map((patient) => `<option value="${escapeHtml(patient.id)}">${escapeHtml(patient.displayName)}</option>`).join('');
    currentSubjectId = patients.some((patient) => patient.id === currentSubjectId) ? currentSubjectId : patients[0].id;
    subjectSelect.value = currentSubjectId;
    subjectSelect.disabled = false;
    subjectSelect.addEventListener('change', () => loadSubject(subjectSelect.value).catch((error) => { status.textContent = `Não foi possível carregar o relatório: ${escapeHtml(error.message)}`; }));
    periodSelect.addEventListener('change', render);
    goalFilter.addEventListener('change', render);
    document.querySelector('[data-refresh-report]')?.addEventListener('click', () => loadSubject(currentSubjectId).catch((error) => { status.textContent = `Falha ao atualizar: ${escapeHtml(error.message)}`; }));
    document.querySelector('[data-print-report]')?.addEventListener('click', () => window.print());
    await loadSubject(currentSubjectId);
  } catch (error) {
    status.textContent = error.status === 401 ? 'Sessão expirada. Redirecionando para o login…' : `Falha ao carregar dados: ${escapeHtml(error.message)}`;
    chart.innerHTML = '<div class="report-empty"><strong>Não foi possível autorizar este relatório.</strong><span>Verifique a sessão e tente novamente.</span></div>';
  }
}
