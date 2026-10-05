-- Refresh tokens opacos: somente o hash é persistido, permitindo rotação de uso único.
create table if not exists refresh_tokens (
  token_hash text primary key,
  user_id text not null references users(id),
  organization_id text not null references organizations(id),
  scopes jsonb not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz
);

create index if not exists refresh_tokens_user_idx
  on refresh_tokens(user_id, revoked_at, expires_at);
