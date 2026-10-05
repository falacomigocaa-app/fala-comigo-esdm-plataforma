import { apiClient } from '../api/client.js';

const levels = { Recusa: 0, 'Ajuda Física': 1, 'Ajuda Verbal': 2, Independente: 3 };
const blocks = ['Lanche', 'Recreio', 'Roda de Conversa', 'Atividade Sentada'];
const escapeHtml = (value) => String(value).replace(/[&<>'"]/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[char]));

function summarize(collections) {
  return blocks.map((block) => {
    const entries = collections.filter((item) => item.blocoRotinaEscolar === block);
    const average = entries.length ? entries.reduce((sum, item) => sum + levels[item.nivelSuporte], 0) / entries.length : null;
    return { block, entries, average };
  });
}

function renderHeader(session) {
  return `<header class="topbar"><a class="brand" href="/escola" data-route="/escola">Fala Comigo <span>Portal</span></a><nav aria-label="Navegação principal"><a href="/clinica" data-route="/clinica" class="nav-link">Clínica</a><a href="/escola" data-route="/escola" class="nav-link selected">Escola</a></nav><div class="session-actions"><span class="session-id">${escapeHtml(session?.userId || '')}</span><button class="text-button" data-logout type="button">Sair</button></div></header>`;
}

export function renderEscolaScreen({ session }) {
  return `<div class="app-shell">${renderHeader(session)}<main class="page-content"><div class="page-heading"><div><p class="eyebrow">Rotina pedagógica</p><h1>Resumo semanal de independência</h1><p class="muted">Histórico carregado pelo portal-api com projeção mínima para o contexto escolar.</p></div><button class="secondary-button" data-refresh-school type="button">Atualizar leitura</button></div><section class="panel highlight-panel"><div><p class="eyebrow">Maior autonomia detectada</p><h2 data-best-block>Carregando…</h2><p class="muted" data-best-description>Aguardando histórico autorizado.</p></div><div class="metric-big" data-best-score>—<small>/ 3</small></div></section><section class="summary-grid" aria-label="Resumo por bloco" data-summary-grid>${blocks.map((block) => `<article class="summary-card"><div class="summary-card-top"><h2>${escapeHtml(block)}</h2><span class="badge local">Carregando</span></div><div class="progress-track"><span style="width:0%"></span></div><p>Consultando API…</p></article>`).join('')}</section><section class="panel"><div class="section-heading"><div><p class="eyebrow">ColetaEscolaModel</p><h2>Histórico da semana</h2></div><span class="form-status" data-school-status>Carregando coletas…</span></div><div class="table-wrap"><table><thead><tr><th>Data</th><th>Bloco</th><th>Nível de suporte</th><th>Valor de autonomia</th></tr></thead><tbody data-collections-body><tr><td colspan="4">Carregando…</td></tr></tbody></table></div></section></main></div>`;
}

export async function hydrateEscolaScreen({ session }) {
  const subjectId = session.subjectId || 'subject-demo-child';
  const status = document.querySelector('[data-school-status]');
  const collectionsBody = document.querySelector('[data-collections-body]');
  const summaryGrid = document.querySelector('[data-summary-grid]');
  const bestBlock = document.querySelector('[data-best-block]');
  const bestDescription = document.querySelector('[data-best-description]');
  const bestScore = document.querySelector('[data-best-score]');
  if (!status || !collectionsBody || !summaryGrid) return;

  const load = async () => {
    status.textContent = 'Consultando histórico autorizado…';
    const result = await apiClient.carregarHistoricoEscolar(subjectId);
    const collections = result.collections || [];
    const summary = summarize(collections);
    const best = summary.filter((item) => item.average !== null).sort((a, b) => b.average - a.average)[0];
    bestBlock.textContent = best ? best.block : 'Sem registros';
    bestDescription.textContent = best ? `Média de ${best.average.toFixed(1)} de 3 no período retornado pela API.` : 'Ainda não há coletas autorizadas.';
    bestScore.innerHTML = `${best ? best.average.toFixed(1) : '—'}<small>/ 3</small>`;
    summaryGrid.innerHTML = summary.map((item) => `<article class="summary-card"><div class="summary-card-top"><h2>${escapeHtml(item.block)}</h2><span class="badge ${item.average === 3 ? 'active' : 'local'}">${item.average === null ? 'Sem dados' : `${item.average.toFixed(1)} / 3`}</span></div><div class="progress-track"><span style="width:${item.average === null ? 0 : (item.average / 3) * 100}%"></span></div><p>${item.entries.length} coleta(s) · ${item.entries.at(-1) ? escapeHtml(item.entries.at(-1).nivelSuporte) : 'aguardando registro'}</p></article>`).join('');
    collectionsBody.innerHTML = collections.length ? collections.map((item) => `<tr><td>${new Date(item.dataRegistro).toLocaleDateString('pt-BR')}</td><td>${escapeHtml(item.blocoRotinaEscolar)}</td><td>${escapeHtml(item.nivelSuporte)}</td><td><strong>${levels[item.nivelSuporte]} / 3</strong></td></tr>`).join('') : '<tr><td colspan="4">Nenhuma coleta no período.</td></tr>';
    status.textContent = `${collections.length} coleta(s) recebida(s) pela API.`;
  };

  await load();
  document.querySelector('[data-refresh-school]')?.addEventListener('click', () => load().catch((error) => { status.textContent = `Falha ao atualizar: ${error.message}`; }));
}
