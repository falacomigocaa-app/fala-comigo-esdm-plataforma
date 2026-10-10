import { apiClient, getSession } from '../api/client.js';
import { decryptCollectionEnvelopes, encryptCollection } from '../services/crypto-web.service.js';

const levels = { Recusa: 0, 'Ajuda Física': 1, 'Ajuda Verbal': 2, Independente: 3 };
const blocks = ['Lanche', 'Recreio', 'Roda de Conversa', 'Atividade Sentada'];
const esc = (value) => String(value ?? '').replace(/[&<>'"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[c]));

export function renderEscolaScreen({ session }) {
  return `<div class="app-shell"><header class="topbar"><a class="brand" href="/clinica" data-route="/clinica">Fala Comigo <span>Portal</span></a><nav aria-label="Navegação principal"><a href="/clinica" data-route="/clinica">Clínica</a><a href="/escola" data-route="/escola">Escola</a><a href="/relatorios" data-route="/relatorios">Relatórios</a><a href="/admin/profissionais" data-route="/admin/profissionais">Profissionais</a><a href="/pacientes" data-route="/pacientes" class="nav-link">Pacientes e acessos</a><a href="/conta" data-route="/conta" class="nav-link">Minha conta</a></nav><button class="text-button" data-logout type="button">Sair</button></header><main class="page-content"><div class="page-heading"><div><h1>Rotina escolar</h1><p class="muted">Registre observações e acompanhe a autonomia com acesso autorizado.</p></div></div><section class="panel"><label for="school-subject">Paciente</label><select id="school-subject" data-school-subject disabled><option>Carregando…</option></select><p data-school-status role="status">Consultando vínculos…</p></section><section class="panel"><h2>Registrar observação</h2><form data-collection-form class="stack-form"><label for="school-block">Momento da rotina</label><select id="school-block" name="block">${blocks.map((block) => `<option>${esc(block)}</option>`).join('')}</select><label for="school-level">Nível de suporte</label><select id="school-level" name="level">${Object.keys(levels).map((level) => `<option>${esc(level)}</option>`).join('')}</select><button class="primary-button" data-save-collection type="submit" disabled>Salvar observação</button><p data-collection-status role="status">${session?.scopes?.includes('school_collection.write') ? 'Selecione um paciente para começar.' : 'Seu acesso permite apenas os recursos autorizados pelo responsável.'}</p></form></section><section class="summary-grid" data-school-summary aria-label="Resumo por rotina"></section><section class="panel"><h2>Histórico dos últimos sete dias</h2><div class="table-wrap"><table><thead><tr><th>Data</th><th>Rotina</th><th>Suporte</th></tr></thead><tbody data-school-history><tr><td colspan="3">Selecione um paciente.</td></tr></tbody></table></div></section></main></div>`;
}

export async function hydrateEscolaScreen({ session }) {
  const select = document.querySelector('[data-school-subject]');
  const status = document.querySelector('[data-school-status]');
  const save = document.querySelector('[data-save-collection]');
  const form = document.querySelector('[data-collection-form]');
  const history = document.querySelector('[data-school-history]');
  const summary = document.querySelector('[data-school-summary]');
  const feedback = document.querySelector('[data-collection-status]');
  if (!select || !status) return;
  let generation = 0;
  const writable = session.scopes?.includes('school_collection.write') && !!session.organizationKey;
  const load = async () => {
    const current = ++generation;
    const subjectId = select.value;
    status.textContent = 'Carregando histórico…';
    const result = await apiClient.carregarHistoricoEscolar(subjectId);
    const records = await decryptCollectionEnvelopes(result.collections || [], { session: getSession() });
    if (current !== generation || !select.isConnected) return;
    const from = Date.now() - 7 * 86400000;
    const recent = records.filter((row) => Date.parse(row.dataRegistro) >= from && Date.parse(row.dataRegistro) <= Date.now());
    history.innerHTML = recent.length ? recent.map((row) => `<tr><td>${esc(new Date(row.dataRegistro).toLocaleString('pt-BR'))}</td><td>${esc(row.blocoRotinaEscolar)}</td><td>${esc(row.nivelSuporte)}</td></tr>`).join('') : '<tr><td colspan="3">Nenhuma observação neste período.</td></tr>';
    summary.innerHTML = blocks.map((block) => {
      const rows = recent.filter((row) => row.blocoRotinaEscolar === block && Object.hasOwn(levels, row.nivelSuporte));
      const score = rows.length ? (rows.reduce((sum, row) => sum + levels[row.nivelSuporte], 0) / rows.length).toFixed(1) : '—';
      return `<article class="summary-card"><h3>${esc(block)}</h3><strong>${score} / 3</strong><p>${rows.length} observações</p></article>`;
    }).join('');
    status.textContent = `${recent.length} observações nos últimos sete dias.`;
  };
  const { subjects = [] } = await apiClient.carregarPacientes(session.organizationId);
  if (!subjects.length) { select.innerHTML = '<option>Nenhum paciente autorizado</option>'; status.textContent = 'Solicite um vínculo e consentimento ao responsável.'; return; }
  select.innerHTML = subjects.map((subject) => `<option value="${esc(subject.id)}">${esc(subject.displayName)}</option>`).join('');
  select.disabled = false; save.disabled = !writable;
  const showError = (error) => { status.textContent = `Não foi possível carregar: ${error.message}`; };
  select.addEventListener('change', () => load().catch(showError));
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (!writable || save.disabled) return;
    const subjectId = select.value;
    save.disabled = true; select.disabled = true;
    feedback.textContent = 'Salvando…';
    try {
      const data = new FormData(form);
      const envelope = await encryptCollection({ subjectId, id: crypto.randomUUID(), dataRegistro: new Date().toISOString(), blocoRotinaEscolar: data.get('block'), nivelSuporte: data.get('level') }, { session: getSession() });
      await apiClient.salvarColeta(subjectId, envelope);
      feedback.textContent = 'Observação salva.';
      await load();
    } catch (error) { feedback.textContent = `Não foi possível salvar: ${error.message}`; }
    finally { save.disabled = !writable; select.disabled = false; }
  });
  await load();
}
