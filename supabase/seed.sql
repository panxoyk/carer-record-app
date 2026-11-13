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
  ('55555555-5555-5555-5555-555555555555', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'camila.vera@example.test', crypt('ChangeMe123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('66666666-6666-6666-6666-666666666666', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'valentina.soto@example.test', crypt('ChangeMe123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('77777777-7777-7777-7777-777777777777', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'felipe.araneda@example.test', crypt('ChangeMe123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('88888888-8888-8888-8888-888888888888', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'carla.vidal@example.test', crypt('ChangeMe123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '')
on conflict (id) do nothing;

insert into public.practitioners (id, display_name, role, license_number, status) values
  ('11111111-1111-1111-1111-111111111111', 'Dra. Ana Torres', 'physician', 'MED-10001', 'active'),
  ('22222222-2222-2222-2222-222222222222', 'Matías Rojas', 'nurse', 'NUR-10002', 'active'),
  ('33333333-3333-3333-3333-333333333333', 'Administración', 'administrator', null, 'active'),
  ('44444444-4444-4444-4444-444444444444', 'Técnico de prueba', 'technician', null, 'active'),
  ('55555555-5555-5555-5555-555555555555', 'Dra. Camila Vera', 'physician', 'MED-10003', 'suspended'),
  ('66666666-6666-6666-6666-666666666666', 'Valentina Soto', 'nurse', 'TENS-10004', 'active'),
  ('77777777-7777-7777-7777-777777777777', 'Felipe Araneda', 'nurse', 'KIN-10005', 'active'),
  ('88888888-8888-8888-8888-888888888888', 'Carla Vidal', 'nurse', 'NUT-10006', 'active')
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

-- ADR-024: demo professions for timeline filters and author snapshots.
update public.organization_memberships m
set profession = demo.profession
from public.profiles p
join (values
  ('11111111-1111-1111-1111-111111111111'::uuid, 'medicina'),
  ('22222222-2222-2222-2222-222222222222'::uuid, 'enfermeria'),
  ('55555555-5555-5555-5555-555555555555'::uuid, 'medicina'),
  ('66666666-6666-6666-6666-666666666666'::uuid, 'tens'),
  ('77777777-7777-7777-7777-777777777777'::uuid, 'kinesiologia'),
  ('88888888-8888-8888-8888-888888888888'::uuid, 'nutricion')
) as demo(auth_user_id, profession) on demo.auth_user_id = p.auth_user_id
where m.profile_id = p.id and m.profession is null;

-- Demo staff can attach clinical photos to open episodes (FHIR DocumentReference).
insert into public.role_permissions (organization_id, role_id, permission_code)
select role.organization_id, role.id, 'clinical.document.create'
from public.roles role
join public.organizations organization on organization.id = role.organization_id
where organization.slug = 'demo-hospital'
  and (role.name = 'Personal clínico' or role.protected_kind = 'demo_administrator')
on conflict (organization_id, role_id, permission_code) do nothing;
