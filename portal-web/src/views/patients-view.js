import { apiClient } from '../api/client.js';
import { esc, header } from './account-views.js';
const scopes = { 'esdm_goal.read':'Ler metas', 'esdm_goal.write':'Registrar metas', 'school_collection.read':'Ler coletas', 'school_collection.write':'Registrar coletas' };
export function renderPatientsView({session}) {
  const create = session.scopes?.includes('subject.create') ? `<section class="panel"><h2>Cadastrar pessoa sob sua responsabilidade</h2><form class="stack-form" data-create-subject><label for="patient-name">Nome de exibição (use apenas o necessário)</label><input id="patient-name" name="displayName" maxlength="80" required><label class="scope-option"><input type="checkbox" name="guardianConfirmed" required><span>Sou responsável legal por essa pessoa e posso autorizar o acompanhamento.</span></label><button class="primary-button">Cadastrar</button><p data-create-status role="status"></p></form></section>` : '';
  return `${header(session)}<main class="page-content"><h1>Pacientes e acessos</h1><p class="muted">Só o responsável pelo cadastro pode autorizar ou revogar o acesso a cada paciente.</p>${create}<section class="panel"><label for="access-patient">Paciente</label><select id="access-patient" data-patient disabled><option>Carregando…</option></select><p data-access-status role="status"></p><div data-owner-only hidden><h2>Autorizar acompanhamento</h2><form class="stack-form" data-access><label for="recipient">Pessoa da equipe</label><select id="recipient" name="recipientUserId" required></select><label for="purpose">Finalidade</label><input id="purpose" name="purpose" maxlength="300" required placeholder="Ex.: acompanhar metas de comunicação"><label for="expiry">Válido até</label><input id="expiry" name="validUntil" type="date" required><fieldset class="scope-fieldset"><legend>Permissões para este paciente</legend>${Object.entries(scopes).map(([id,label])=>`<label class="scope-option"><input type="checkbox" name="scopes" value="${id}"><span>${label}</span></label>`).join('')}</fieldset><label class="scope-option"><input type="checkbox" name="consentConfirmed" required><span>Autorizo os acessos selecionados para a finalidade e o prazo informados. Posso revogar a autorização aqui.</span></label><button class="primary-button">Conceder acesso</button><p data-grant-status role="status"></p></form><h2>Acessos concedidos</h2><div class="table-wrap"><table><thead><tr><th>Pessoa</th><th>Finalidade e prazo</th><th>Status</th><th>Ação</th></tr></thead><tbody data-grants></tbody></table></div></div></section></main>`;
}
export async function hydratePatientsView({session}) {
  const selector = document.querySelector('[data-patient]');
  const status = document.querySelector('[data-access-status]');
  const ownerArea = document.querySelector('[data-owner-only]');
  const grantForm = document.querySelector('[data-access]');
  const grantStatus = document.querySelector('[data-grant-status]');
  const rows = document.querySelector('[data-grants]');
  let patients = [], people = [], generation = 0;
  async function loadGrants() {
    const selected = selector.value, current = ++generation;
    const owner = patients.find((patient) => patient.id === selected)?.isOwner;
    ownerArea.hidden = !owner;
    rows.innerHTML = '';
    if (!owner) { status.textContent = 'Você pode usar os recursos autorizados pelo responsável nas demais telas.'; return; }
    status.textContent = '';
    const result = await apiClient.request(`/v1/subjects/${encodeURIComponent(selected)}/access`);
    if (current !== generation) return;
    rows.innerHTML = result.grants.length ? result.grants.map((grant) => `<tr><td>${esc(people.find((person)=>person.id===grant.userId)?.email || grant.userId)}</td><td>${esc(grant.purpose)}<br>${esc(new Date(grant.validUntil).toLocaleDateString('pt-BR'))}</td><td>${esc(grant.status)}</td><td>${grant.status === 'active' ? `<button class="text-button" type="button" data-revoke="${esc(grant.id)}">Revogar</button>` : '—'}</td></tr>`).join('') : '<tr><td colspan="4">Nenhum acesso concedido.</td></tr>';
    rows.querySelectorAll('[data-revoke]').forEach((button) => button.addEventListener('click', async () => {
      button.disabled = true;
      try { await apiClient.request(`/v1/subjects/${encodeURIComponent(selected)}/grants/${encodeURIComponent(button.dataset.revoke)}/revoke`, {method:'POST'}); await loadGrants(); grantStatus.textContent = 'Acesso revogado.'; }
      catch (_) { grantStatus.textContent = 'Não foi possível revogar. Tente novamente.'; button.disabled = false; }
    }));
  }
  async function loadPatients() {
    const result = await apiClient.carregarPacientes(session.organizationId); patients = result.subjects;
    selector.innerHTML = patients.map((patient)=>`<option value="${esc(patient.id)}">${esc(patient.displayName)}</option>`).join('') || '<option>Nenhum paciente autorizado</option>';
    selector.disabled = !patients.length;
    if (patients.length) await loadGrants(); else ownerArea.hidden = true;
  }
  const team = await apiClient.request(`/v1/organizations/${encodeURIComponent(session.organizationId)}/people`); people = team.people;
  const recipient = grantForm.elements.recipientUserId;
  recipient.innerHTML = people.filter((person)=>person.id !== session.userId).map((person)=>`<option value="${esc(person.id)}">${esc(person.email)} (${esc(person.role)})</option>`).join('');
  function updateScopes() {
    const person = people.find((item)=>item.id===recipient.value);
    grantForm.querySelectorAll('[name=scopes]').forEach((input)=>{ input.checked=false; input.disabled=!person?.scopes.includes(input.value); });
    grantForm.querySelector('button').disabled = !person;
  }
  recipient.addEventListener('change',updateScopes); updateScopes();
  selector.addEventListener('change',()=>loadGrants().catch(()=>{status.textContent='Falha ao carregar acessos.';}));
  document.querySelector('[data-create-subject]')?.addEventListener('submit',async(event)=>{
    event.preventDefault(); const form=event.currentTarget, message=form.querySelector('[data-create-status]'), button=form.querySelector('button'); button.disabled=true;
    try { await apiClient.request('/v1/subjects',{method:'POST',body:{displayName:form.elements.displayName.value,guardianConfirmed:form.elements.guardianConfirmed.checked}}); form.reset(); message.textContent='Cadastro criado.'; await loadPatients(); }
    catch(_){message.textContent='Não foi possível cadastrar. Confira os dados e a sessão.';} finally{button.disabled=false;}
  });
  grantForm.addEventListener('submit',async(event)=>{
    event.preventDefault(); const button=grantForm.querySelector('button'); button.disabled=true;
    const data=new FormData(grantForm);
    try { await apiClient.request(`/v1/subjects/${encodeURIComponent(selector.value)}/access`,{method:'POST',body:{recipientUserId:data.get('recipientUserId'),purpose:data.get('purpose'),validUntil:`${data.get('validUntil')}T23:59:59.000Z`,scopes:data.getAll('scopes'),consentConfirmed:data.has('consentConfirmed')}}); await loadGrants(); grantStatus.textContent='Acesso concedido para o prazo e a finalidade informados.'; }
    catch(_){grantStatus.textContent='Confira as permissões e um prazo futuro de até um ano.';} finally{button.disabled=false;}
  });
  await loadPatients();
}
