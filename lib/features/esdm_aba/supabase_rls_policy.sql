-- Política documental do backend Cuidado Conectado.
-- A aplicação Flutter continua local-first; este script representa a
-- autorização server-side que deverá existir antes da sincronização real.

create table if not exists public.coletas (
  id uuid primary key,
  paciente_id uuid not null references auth.users(id),
  responsavel_id uuid not null references auth.users(id),
  bloco_rotina_escolar text not null,
  nivel_suporte text not null,
  payload_json jsonb not null default '{}'::jsonb,
  data_registro timestamptz not null,
  data_expiracao timestamptz not null,
  created_at timestamptz not null default now()
);

alter table public.coletas enable row level security;

create policy "Permitir leitura apenas com token valido"
on coletas for select
using (
  auth.uid() = paciente_id
  and data_expiracao > now()
);

-- Escrita exige que o usuário autenticado seja o responsável autorizado.
create policy "Permitir insercao apenas ao responsavel autorizado"
on coletas for insert
with check (
  auth.uid() = responsavel_id
  and data_expiracao > now()
);

create policy "Permitir atualizacao apenas ao responsavel autorizado"
on coletas for update
using (
  auth.uid() = responsavel_id
  and data_expiracao > now()
)
with check (
  auth.uid() = responsavel_id
  and data_expiracao > now()
);

create index if not exists coletas_paciente_expiracao_idx
  on public.coletas (paciente_id, data_expiracao);
