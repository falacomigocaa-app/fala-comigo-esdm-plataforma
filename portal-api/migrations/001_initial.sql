-- Gate 3A: schema sintético de autorização do portal.
-- Não contém dados reais, senhas, tokens ou credenciais.

create table if not exists users (
  id text primary key,
  external_subject text not null unique,
  status text not null check (status in ('active', 'disabled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists organizations (
  id text primary key,
  name text not null,
  type text not null check (type in ('family', 'school', 'clinic', 'sponsor')),
  status text not null check (status in ('active', 'suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists memberships (
  id text primary key,
  user_id text not null references users(id),
  organization_id text not null references organizations(id),
  role text not null check (role in ('owner', 'org_admin', 'professional', 'caregiver', 'outsider')),
  status text not null check (status in ('active', 'revoked', 'expired')),
  valid_until timestamptz not null,
  unique (user_id, organization_id)
);

create table if not exists child_subjects (
  id text primary key,
  family_space_id text not null,
  owner_user_id text not null references users(id),
  display_name text not null,
  status text not null check (status in ('active', 'archived')),
  created_at timestamptz not null default now()
);

create table if not exists consents (
  id text primary key,
  subject_id text not null references child_subjects(id),
  organization_id text not null references organizations(id),
  granted_by_user_id text not null references users(id),
  recipient_user_id text not null references users(id),
  purpose text not null,
  scopes text[] not null default '{}',
  notice_version text not null,
  status text not null check (status in ('active', 'revoked', 'expired')),
  valid_until timestamptz not null,
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);

create table if not exists invitations (
  id text primary key,
  organization_id text not null references organizations(id),
  invitee_user_id text not null references users(id),
  subject_id text references child_subjects(id),
  consent_id text references consents(id),
  purpose text,
  scopes text[] not null default '{}',
  role text not null check (role in ('org_admin', 'professional', 'caregiver')),
  status text not null check (status in ('pending', 'accepted', 'declined', 'expired', 'revoked')),
  expires_at timestamptz not null
);

create table if not exists care_relationships (
  id text primary key,
  user_id text not null references users(id),
  subject_id text not null references child_subjects(id),
  organization_id text not null references organizations(id),
  role text not null,
  status text not null check (status in ('active', 'revoked', 'expired')),
  valid_until timestamptz not null,
  unique (user_id, subject_id, organization_id)
);

create table if not exists access_grants (
  id text primary key,
  user_id text not null references users(id),
  subject_id text not null references child_subjects(id),
  organization_id text not null references organizations(id),
  consent_id text not null references consents(id),
  purpose text not null,
  scopes text[] not null default '{}',
  status text not null check (status in ('active', 'revoked', 'expired')),
  valid_until timestamptz not null
);

create table if not exists benefit_entitlements (
  id text primary key,
  organization_id text not null references organizations(id),
  status text not null check (status in ('active', 'suspended', 'expired', 'revoked')),
  valid_until timestamptz not null
);

create table if not exists audit_events (
  id text primary key,
  user_id text references users(id),
  organization_id text references organizations(id),
  action text not null,
  result text not null check (result in ('allowed', 'denied')),
  code text,
  request_id text,
  occurred_at timestamptz not null,
  api_version text not null
);

create unique index if not exists audit_events_request_id_idx
  on audit_events(request_id)
  where request_id is not null;

create index if not exists consents_subject_idx on consents(subject_id, organization_id, status);
create index if not exists grants_subject_user_idx on access_grants(subject_id, user_id, status);
create index if not exists relationships_subject_user_idx on care_relationships(subject_id, user_id, status);

-- Cuidado Conectado: dados funcionais mínimos, sempre ligados a sujeito e autorização.
create table if not exists esdm_goals (
  id text primary key,
  subject_id text not null references child_subjects(id),
  codigo_tecnico_denver text not null,
  missao_pais text not null,
  dica_pratica text not null,
  status text not null check (status in ('Adquirido', 'Em Progresso', 'Archived')),
  passo_atual_aba integer not null default 1 check (passo_atual_aba >= 0),
  created_by_user_id text not null references users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists school_collections (
  id text primary key,
  subject_id text not null references child_subjects(id),
  data_registro timestamptz not null,
  bloco_rotina_escolar text not null check (bloco_rotina_escolar in ('Lanche', 'Recreio', 'Roda de Conversa', 'Atividade Sentada')),
  nivel_suporte text not null check (nivel_suporte in ('Independente', 'Ajuda Verbal', 'Ajuda Física', 'Recusa')),
  created_by_user_id text not null references users(id),
  created_at timestamptz not null default now()
);

create index if not exists esdm_goals_subject_idx on esdm_goals(subject_id, status, created_at desc);
create index if not exists school_collections_subject_idx on school_collections(subject_id, data_registro desc);
