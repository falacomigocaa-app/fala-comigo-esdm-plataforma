-- Explicit scoped memberships and single-use account activation links.
alter table memberships add column if not exists scopes text[];
alter table memberships drop constraint if exists memberships_role_check;
alter table memberships add constraint memberships_role_check check (role in ('owner','org_admin','professional','teacher','caregiver','outsider'));
alter table invitations drop constraint if exists invitations_role_check;
alter table invitations add constraint invitations_role_check check (role in ('org_admin','professional','teacher','caregiver'));
create table if not exists activation_tokens (
  id text primary key,
  invitation_id text not null references invitations(id),
  user_id text not null references users(id),
  expires_at timestamptz not null,
  used_at timestamptz
);
