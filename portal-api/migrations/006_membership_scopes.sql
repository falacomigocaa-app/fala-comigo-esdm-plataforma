-- Persistência de escopos explícitos por vínculo.
-- NULL preserva o comportamento padrão derivado do papel; array vazio representa
-- deliberadamente um vínculo sem escopos adicionais.
alter table memberships
  add column if not exists scopes text[];

create index if not exists memberships_organization_status_idx
  on memberships(organization_id, status, valid_until);
