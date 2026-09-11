-- Local development only. Password for these accounts: ChangeMe123!
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ana.torres@example.test', crypt('ChangeMe123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'matias.rojas@example.test', crypt('ChangeMe123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin@example.test', crypt('ChangeMe123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('44444444-4444-4444-4444-444444444444', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'tecnico@example.test', crypt('ChangeMe123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '')
on conflict (id) do nothing;

insert into public.practitioners (id, display_name, role, license_number) values
  ('11111111-1111-1111-1111-111111111111', 'Dra. Ana Torres', 'physician', 'MED-10001'),
  ('22222222-2222-2222-2222-222222222222', 'Matías Rojas', 'nurse', 'NUR-10002'),
  ('33333333-3333-3333-3333-333333333333', 'Administración', 'administrator', null),
  ('44444444-4444-4444-4444-444444444444', 'Técnico de prueba', 'technician', null)
on conflict (id) do nothing;

-- Fictitious local-development patients only; never use clinical data here.
insert into public.patients (
  id, external_reference, given_name, family_name, birth_date, rut, care_unit,
  bed_label, payload
) values
  (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'LOCAL-0001',
    'Elena',
    'Pérez',
    '1984-05-16',
    '12.345.678-k',
    'Medicina interna',
    'Cama 12',
    '{"contact_preference":"phone"}'::jsonb
  ),
  (
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'LOCAL-0002',
    'Gabriel',
    'Soto',
    '1977-11-02',
    '9.876.543-2',
    'Cirugía',
    'Cama 07',
    '{"contact_preference":"email"}'::jsonb
  )
on conflict (id) do nothing;

-- Fictitious read-only timeline entries for local development.
insert into public.clinical_events (
  id, patient_id, recorded_by, kind, occurred_at, payload
) values
  (
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '11111111-1111-1111-1111-111111111111',
    'observation', now() - interval '2 hours',
    '{"summary":"Paciente en reposo, sin cambios relevantes."}'::jsonb
  ),
  (
    'dddddddd-dddd-dddd-dddd-dddddddddddd',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '22222222-2222-2222-2222-222222222222',
    'procedure', now() - interval '1 day',
    '{"summary":"Se completó control de signos vitales."}'::jsonb
  ),
  (
    'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    '44444444-4444-4444-4444-444444444444',
    'encounter', now() - interval '3 hours',
    '{"summary":"Evaluación de turno realizada."}'::jsonb
  )
on conflict (id) do nothing;
