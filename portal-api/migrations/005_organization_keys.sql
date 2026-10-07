-- Cofre de chaves por organização: key_encrypted contém um envelope AES-256-GCM
-- cifrado com MASTER_CRYPTO_KEY e nunca armazena a chave AES em plaintext.
create table if not exists organization_keys (
  organization_id text primary key references organizations(id),
  key_encrypted text not null,
  key_version integer not null default 1 check (key_version > 0),
  created_by_user_id text not null references users(id),
  rotated_by_user_id text not null references users(id),
  created_at timestamptz not null default now(),
  rotated_at timestamptz not null default now()
);

create index if not exists organization_keys_rotated_idx
  on organization_keys(rotated_at desc);
