-- Gate P0: toda meta ESDM deve pertencer explicitamente a uma organização.
-- A coluna começa nullable para permitir classificação segura de eventuais legados;
-- o portal-api só cria e consulta metas com organization_id.
alter table esdm_goals
  add column if not exists organization_id text references organizations(id);

create index if not exists esdm_goals_organization_subject_idx
  on esdm_goals(organization_id, subject_id, status, created_at desc);

-- Não aplicar NOT NULL automaticamente: registros legados devem ser classificados
-- pelo responsável antes de qualquer backfill destrutivo ou bloqueio de migração.
