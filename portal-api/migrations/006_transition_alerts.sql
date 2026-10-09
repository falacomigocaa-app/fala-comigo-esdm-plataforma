-- Sombra remota opcional dos alertas locais de transição.
-- O conteúdo é limitado ao payload do alerta autorizado; caminhos de mídia local
-- nunca são enviados pelo mobile.
create table if not exists transition_alerts (
  alert_id text not null,
  subject_id text not null references child_subjects(id),
  organization_id text not null references organizations(id),
  payload jsonb not null,
  client_updated_at timestamptz not null,
  created_by_user_id text not null references users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (subject_id, alert_id)
);

create index if not exists transition_alerts_subject_idx
  on transition_alerts(subject_id, organization_id, client_updated_at desc);
