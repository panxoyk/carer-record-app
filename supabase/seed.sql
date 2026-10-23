-- Local development only. Password for these accounts: ChangeMe123!
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ana.torres@example.test', crypt('ChangeMe123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'matias.rojas@example.test', crypt('ChangeMe123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin@example.test', crypt('ChangeMe123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('44444444-4444-4444-4444-444444444444', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'tecnico@example.test', crypt('ChangeMe123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('55555555-5555-5555-5555-555555555555', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'camila.vera@example.test', crypt('ChangeMe123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '')
on conflict (id) do nothing;

insert into public.practitioners (id, display_name, role, license_number, status) values
  ('11111111-1111-1111-1111-111111111111', 'Dra. Ana Torres', 'physician', 'MED-10001', 'active'),
  ('22222222-2222-2222-2222-222222222222', 'Matías Rojas', 'nurse', 'NUR-10002', 'active'),
  ('33333333-3333-3333-3333-333333333333', 'Administración', 'administrator', null, 'active'),
  ('44444444-4444-4444-4444-444444444444', 'Técnico de prueba', 'technician', null, 'active'),
  ('55555555-5555-5555-5555-555555555555', 'Dra. Camila Vera', 'physician', 'MED-10003', 'suspended')
on conflict (id) do nothing;

-- IAM migrations run before this seed; populate the identity bridge idempotently.
select public.bootstrap_legacy_practitioner_iam();

-- Demo staff can publish synthetic context milestones under the existing delegation contract.
insert into public.role_permissions (organization_id, role_id, permission_code)
select role.organization_id, role.id, permission.code
from public.roles role
join public.organizations organization on organization.id = role.organization_id
join (values ('context.note.read'), ('context.note.create'), ('context.note.confirm')) as permission(code) on true
where organization.slug = 'demo-hospital'
  and (role.name = 'Personal clínico' or role.protected_kind = 'demo_administrator')
on conflict (organization_id, role_id, permission_code) do nothing;
