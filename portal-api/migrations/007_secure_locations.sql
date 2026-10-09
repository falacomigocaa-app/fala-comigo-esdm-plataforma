-- Localizações são recebidas somente como envelope E2EE.
-- O portal não armazena latitude/longitude em claro.
create table if not exists location_updates (
  id text primary key,
  subject_id text not null references child_subjects(id),
  organization_id text not null references organizations(id),
  encrypted_data text not null,
  iv text not null,
  client_recorded_at timestamptz not null,
  created_by_user_id text not null references users(id),
  created_at timestamptz not null default now()
);

create index if not exists location_updates_subject_idx
  on location_updates(subject_id, organization_id, client_recorded_at desc);
