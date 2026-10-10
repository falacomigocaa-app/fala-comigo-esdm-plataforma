import { apiClient } from '../api/client.js';
import { esc, header } from './account-views.js';
export const ADMIN_SCOPE_OPTIONS = [
  {value:'esdm_goal.read',label:'Ler metas'}, {value:'esdm_goal.write',label:'Registrar metas'},
  {value:'school_collection.read',label:'Ler coletas'}, {value:'school_collection.write',label:'Registrar coletas'},
  {value:'organization.key.read',label:'Usar chave da organização para coletas e relatórios'},
  {value:'subject.create',label:'Cadastrar pessoa sob responsabilidade legal'},
  {value:'membership.read',label:'Consultar equipe'}, {value:'access.invite',label:'Gerenciar equipe'}
];
const roleAllowed = {
  professional:['esdm_goal.read','esdm_goal.write','school_collection.read','school_collection.write','organization.key.read'],
  teacher:['esdm_goal.read','school_collection.read','school_collection.write','organization.key.read'],
  caregiver:['subject.create','esdm_goal.read','school_collection.read','organization.key.read'],
  org_admin:['esdm_goal.read','esdm_goal.write','school_collection.read','school_collection.write','organization.key.read','membership.read','access.invite']
};
export const scopesForMember = (member) => Array.isArray(member?.scopes) ? member.scopes : [];
export const hasAdministrativeScope = (session) => session?.scopes?.some((scope)=>['membership.read','access.invite'].includes(scope)) ?? false;
export function renderMembers(members, session = {}) {
  if (!members.length) return '<tr><td colspan="5">Nenhum profissional vinculado.</td></tr>';
  return members.map((member)=>`<tr><td>${esc(member.email || member.userId)}</td><td>${esc(member.role)}</td><td><div class="scope-badges">${scopesForMember(member).map((scope)=>`<span class="scope-badge">${esc(scope)}</span>`).join('') || 'Nenhum escopo'}</div></td><td>${esc(member.status)}</td><td>${member.role !== 'owner' && member.userId !== session.userId && session.scopes?.includes('access.invite') ? `<button type="button" class="text-button" data-edit="${esc(member.id)}">Editar acesso</button>` : '—'}</td></tr>`).join('');
}
export function renderAdminProfessionalsView({session}) {
  if (!hasAdministrativeScope(session)) return `${header(session)}<main class="page-content"><section class="panel access-denied"><h1>Acesso Negado</h1><p>Seu perfil não permite gerenciar a equipe.</p></section></main>`;
  return `${header(session)}<main class="page-content"><h1>Profissionais e escopos</h1><p>Organização: ${esc(session.organizationId)}</p><section class="panel"><h2>Equipe vinculada</h2><p role="status" data-admin-status></p><div class="table-wrap"><table><thead><tr><th>Conta</th><th>Perfil</th><th>Permissões</th><th>Status</th><th>Ação</th></tr></thead><tbody data-admin-members></tbody></table></div></section>${session.scopes?.includes('access.invite') ? `<section class="panel"><h2>Convites pendentes</h2><div data-pending></div><h2 data-form-title>Convidar uma nova conta</h2><p>O destinatário cria a própria senha. O convite não concede acesso a pacientes sem consentimento do responsável.</p><form class="stack-form" data-admin-form><label for="account-email">Email</label><input id="account-email" type="email" name="email" autocomplete="off" required><label for="account-role">Perfil</label><select id="account-role" name="role"><option value="professional">Profissional clínico</option><option value="teacher">Escola</option><option value="caregiver">Responsável legal</option><option value="org_admin">Administrador</option></select><fieldset class="scope-fieldset"><legend>Permissões máximas do vínculo</legend>${ADMIN_SCOPE_OPTIONS.map(({value,label})=>`<label class="scope-option"><input type="checkbox" name="scopes" value="${value}"><span>${label}</span></label>`).join('')}</fieldset><div data-member-fields hidden><label for="member-status">Status</label><select name="status" id="member-status"><option value="active">Ativo</option><option value="revoked">Revogado</option></select><label for="member-expiry">Validade do vínculo</label><input name="validUntil" id="member-expiry" type="date"></div><button class="primary-button" data-submit>Criar convite</button><button class="secondary-button" data-cancel type="button" hidden>Cancelar edição</button><p role="status" data-admin-form-status></p></form><div data-invitation-result hidden><p>Link pessoal de ativação: compartilhe somente com o destinatário por um canal privado. Ele vale por sete dias.</p><label for="activation-link">Link de ativação</label><input id="activation-link" readonly autocomplete="off"><button type="button" class="secondary-button" data-copy>Copiar link</button></div></section>` : ''}</main>`;
}
export async function hydrateAdminProfessionalsView({session}) {
  if (!hasAdministrativeScope(session)) return;
  const status=document.querySelector('[data-admin-status]'), rows=document.querySelector('[data-admin-members]');
  const form=document.querySelector('[data-admin-form]'); let members=[], editing=null;
  const syncOptions=()=>{if(!form)return; form.querySelectorAll('[name=scopes]').forEach((input)=>{input.disabled=!roleAllowed[form.elements.role.value]?.includes(input.value)||!session.scopes.includes(input.value); if(input.disabled)input.checked=false;});};
  const reset=()=>{editing=null;form.reset();form.elements.email.disabled=false;document.querySelector('[data-member-fields]').hidden=true;document.querySelector('[data-cancel]').hidden=true;document.querySelector('[data-form-title]').textContent='Convidar uma nova conta';document.querySelector('[data-submit]').textContent='Criar convite';syncOptions();};
  async function load(){
    const result=await apiClient.carregarProfissionais(session.organizationId);
    members=result.memberships;rows.innerHTML=renderMembers(members,session);status.textContent=`${members.length} vínculo(s).`;
    if (form) {
      const pending = await apiClient.request(`/v1/organizations/${encodeURIComponent(session.organizationId)}/account-invitations`);
      const area = document.querySelector('[data-pending]');
      area.innerHTML = pending.invitations.map((item) => `<p>${esc(item.email)} <button type="button" class="text-button" data-reissue="${esc(item.id)}">Gerar novo link</button></p>`).join('') || '<p class="muted">Nenhum convite pendente.</p>';
      area.querySelectorAll('[data-reissue]').forEach((button) => button.addEventListener('click', async () => {
        button.disabled = true;
        try {
          const result = await apiClient.request(`/v1/organizations/${encodeURIComponent(session.organizationId)}/account-invitations/${encodeURIComponent(button.dataset.reissue)}/reissue`, { method:'POST' });
          document.querySelector('#activation-link').value = `${window.location.origin}/ativar#token=${encodeURIComponent(result.token)}`;
          document.querySelector('[data-invitation-result]').hidden = false;
          document.querySelector('[data-admin-form-status]').textContent = 'Novo link criado. O anterior deixou de valer.';
        } catch (_) { document.querySelector('[data-admin-form-status]').textContent = 'Não foi possível renovar o convite.'; }
        finally { button.disabled = false; }
      }));
    }
    rows.querySelectorAll('[data-edit]').forEach((button)=>button.addEventListener('click',()=>{
      editing=members.find((member)=>member.id===button.dataset.edit);if(!form||!editing)return;
      form.elements.email.value=editing.email||'';form.elements.email.disabled=true;form.elements.role.value=editing.role;form.elements.status.value=editing.status;form.elements.validUntil.value=editing.validUntil.slice(0,10);
      syncOptions();form.querySelectorAll('[name=scopes]').forEach((input)=>{input.checked=!input.disabled&&editing.scopes.includes(input.value);});
      document.querySelector('[data-member-fields]').hidden=false;document.querySelector('[data-cancel]').hidden=false;document.querySelector('[data-form-title]').textContent='Editar vínculo';document.querySelector('[data-submit]').textContent='Salvar acesso';document.querySelector('[data-invitation-result]').hidden=true;
    }));
  }
  if(form){
    reset();form.elements.role.addEventListener('change',syncOptions);document.querySelector('[data-cancel]').addEventListener('click',reset);
    document.querySelector('[data-copy]').addEventListener('click',async()=>{const input=document.querySelector('#activation-link');try{await navigator.clipboard.writeText(input.value);}catch(_){input.select();}});
    form.addEventListener('submit',async(event)=>{
      event.preventDefault();const button=document.querySelector('[data-submit]'),message=document.querySelector('[data-admin-form-status]');button.disabled=true;document.querySelector('[data-invitation-result]').hidden=true;
      const data=new FormData(form),body={role:data.get('role'),scopes:data.getAll('scopes')};
      try{
        if(editing){await apiClient.request(`/v1/organizations/${encodeURIComponent(session.organizationId)}/member-access/${encodeURIComponent(editing.id)}`,{method:'POST',body:{...body,status:data.get('status'),validUntil:`${data.get('validUntil')}T23:59:59.000Z`}});reset();message.textContent='Vínculo atualizado. Permissões removidas deixam de valer imediatamente; novos acessos exigem novo login.';}
        else{const result=await apiClient.request(`/v1/organizations/${encodeURIComponent(session.organizationId)}/account-invitations`,{method:'POST',body:{...body,email:data.get('email')}});reset();document.querySelector('#activation-link').value=`${window.location.origin}/ativar#token=${encodeURIComponent(result.token)}`;document.querySelector('[data-invitation-result]').hidden=false;message.textContent='Convite criado. Guarde o link: ele só é exibido nesta sessão.';}
        await load();
      }catch(error){message.textContent=error.message==='ACCOUNT_EXISTS'?'Essa conta já existe. Gerencie seu vínculo ou solicite suporte.':'Não foi possível salvar. Confira email, permissões, prazo e sessão.';}finally{button.disabled=false;}
    });
  }
  await load();
}
