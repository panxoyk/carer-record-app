-- Local development only. Password for these accounts: ChangeMe123!
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ana.torres@example.test', crypt('ChangeMe123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'matias.rojas@example.test', crypt('ChangeMe123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin@example.test', crypt('ChangeMe123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now())
on conflict (id) do nothing;

insert into public.practitioners (id, display_name, role, license_number) values
  ('11111111-1111-1111-1111-111111111111', 'Dra. Ana Torres', 'physician', 'MED-10001'),
  ('22222222-2222-2222-2222-222222222222', 'Matías Rojas', 'nurse', 'NUR-10002'),
  ('33333333-3333-3333-3333-333333333333', 'Administración', 'administrator', null)
on conflict (id) do nothing;
