-- Billing sandbox: não armazena cartão, CVV, conta bancária ou dados financeiros.
create table if not exists subscriptions (
  id text primary key,
  organization_id text not null references organizations(id),
  plan_id text not null,
  status text not null check (status in ('pending_payment', 'active', 'grace', 'suspended', 'canceled', 'expired')),
  provider text not null default 'sandbox',
  provider_customer_id text,
  provider_subscription_id text unique,
  current_period_start timestamptz,
  current_period_end timestamptz,
  cancel_at_period_end boolean not null default false,
  created_by_user_id text not null references users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists subscriptions_active_org_idx
  on subscriptions(organization_id)
  where status in ('pending_payment', 'active', 'grace');

create index if not exists subscriptions_org_idx
  on subscriptions(organization_id, updated_at desc);

create table if not exists billing_events (
  id text primary key,
  provider text not null default 'sandbox',
  event_type text not null,
  payload_hash text not null,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  status text not null check (status in ('received', 'processed', 'ignored', 'failed')),
  error_code text
);
