-- A request identifier is scoped by actor, organization, method and resource in the API.
create table if not exists idempotency_records (
  id text primary key,
  payload_hash text not null,
  result jsonb not null,
  created_at timestamptz not null default now()
);
-- Every retry/denial is a separate audit event, even when its request ID is reused.
drop index if exists audit_events_request_id_idx;
create index if not exists audit_events_request_lookup_idx on audit_events(request_id);
