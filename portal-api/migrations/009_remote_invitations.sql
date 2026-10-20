-- Convites remotos: destinatário identificável e token de aceite sem guardar o token bruto.
alter table invitations
  alter column invitee_user_id drop not null;

alter table invitations
  add column if not exists invitee_email text,
  add column if not exists invitee_phone text,
  add column if not exists token_hash text,
  add column if not exists created_by_user_id text references users(id),
  add column if not exists created_at timestamptz not null default now();

create unique index if not exists invitations_token_hash_idx
  on invitations(token_hash)
  where token_hash is not null;

create index if not exists invitations_recipient_idx
  on invitations(invitee_email, status, expires_at);
