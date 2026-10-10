-- Reports técnicos do beta: sem conteúdo clínico, identificadores de paciente ou prontuário.
create table if not exists beta_bug_reports (
  id text primary key,
  user_id text not null references users(id),
  organization_id text not null references organizations(id),
  severity text not null check (severity in ('leve', 'travamento', 'sugestao')),
  description text not null check (char_length(description) between 1 and 2000),
  app_version text not null,
  platform text not null check (platform in ('web', 'android', 'unknown')),
  user_agent text not null default '',
  device_model text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists beta_bug_reports_created_idx on beta_bug_reports(created_at desc);
create index if not exists beta_bug_reports_organization_idx on beta_bug_reports(organization_id, created_at desc);
alter table beta_bug_reports enable row level security;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'create policy "beta reports service role only" on beta_bug_reports for all to service_role using (true) with check (true)';
  end if;
exception
  when duplicate_object then null;
end $$;
