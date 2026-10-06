-- Fixtures sintéticos somente para o job de integração do GitHub Actions.
-- Não contém dados de produção nem segredos reutilizáveis.
insert into users (id, external_subject, status, email, password_hash) values
  ('user-admin-alpha', 'synthetic:admin-alpha', 'active', 'admin@fala-comigo.test', '$2b$12$u7hinMZXhMWNJXvBs90RauPnmv8zVvZcSh7ohICCg/S9TJAESRqSi'),
  ('user-professional-alpha', 'synthetic:professional-alpha', 'active', 'profissional@fala-comigo.test', '$2b$12$u7hinMZXhMWNJXvBs90RauPnmv8zVvZcSh7ohICCg/S9TJAESRqSi'),
  ('user-admin-beta', 'synthetic:admin-beta', 'active', 'admin.beta@fala-comigo.test', '$2b$12$u7hinMZXhMWNJXvBs90RauPnmv8zVvZcSh7ohICCg/S9TJAESRqSi'),
  ('user-outsider', 'synthetic:outsider', 'active', 'outsider@fala-comigo.test', '$2b$12$u7hinMZXhMWNJXvBs90RauPnmv8zVvZcSh7ohICCg/S9TJAESRqSi'),
  ('user-invitee-alpha', 'synthetic:invitee-alpha', 'active', 'invitee@fala-comigo.test', '$2b$12$u7hinMZXhMWNJXvBs90RauPnmv8zVvZcSh7ohICCg/S9TJAESRqSi')
on conflict (id) do nothing;

insert into organizations (id, name, type, status) values
  ('org-demo-alpha', 'Clínica Aurora Demo', 'clinic', 'active'),
  ('org-demo-beta', 'Escola Horizonte Demo', 'school', 'active')
on conflict (id) do nothing;

insert into memberships (id, user_id, organization_id, role, status, valid_until) values
  ('membership-admin-alpha', 'user-admin-alpha', 'org-demo-alpha', 'owner', 'active', '2099-01-01T00:00:00Z'),
  ('membership-professional-alpha', 'user-professional-alpha', 'org-demo-alpha', 'professional', 'active', '2099-01-01T00:00:00Z'),
  ('membership-admin-beta', 'user-admin-beta', 'org-demo-beta', 'owner', 'active', '2099-01-01T00:00:00Z')
on conflict (id) do nothing;

insert into child_subjects (id, family_space_id, owner_user_id, display_name, status)
values ('subject-demo-child', 'family-demo-alpha', 'user-admin-alpha', 'Criança Demo', 'active')
on conflict (id) do nothing;
