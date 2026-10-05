-- Credenciais locais do provedor central: somente hashes bcrypt são armazenados.
alter table users add column if not exists email text;
alter table users add column if not exists password_hash text;

create unique index if not exists users_email_lower_idx
  on users (lower(email))
  where email is not null;
