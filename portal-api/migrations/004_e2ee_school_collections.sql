-- Armazena o envelope E2EE sem exigir que o portal-api conheça a chave do cliente.
alter table school_collections
  add column if not exists organization_id text references organizations(id),
  add column if not exists encrypted_data text,
  add column if not exists iv text;

-- Registros legados podem continuar com os campos claros; novos registros E2EE
-- usam organization_id/encrypted_data/iv e deixam os campos clínicos nulos.
alter table school_collections
  alter column bloco_rotina_escolar drop not null,
  alter column nivel_suporte drop not null;

create index if not exists school_collections_organization_idx
  on school_collections(organization_id, data_registro desc);
