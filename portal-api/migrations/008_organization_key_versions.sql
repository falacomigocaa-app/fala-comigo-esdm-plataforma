-- Histórico de chaves E2EE por organização.
-- Cada versão continua cifrada pelo MASTER_CRYPTO_KEY; o portal nunca persiste
-- a chave da organização em claro.
create table if not exists organization_key_versions (
  organization_id text not null references organizations(id),
  key_version integer not null,
  key_encrypted text not null,
  created_by_user_id text not null references users(id),
  created_at timestamptz not null default now(),
  retired_at timestamptz,
  primary key (organization_id, key_version)
);

create index if not exists organization_key_versions_active_idx
  on organization_key_versions(organization_id, key_version desc)
  where retired_at is null;
