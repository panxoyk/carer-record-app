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

-- IAM migrations run before this seed. Populate the additive identity bridge after
-- synthetic legacy practitioners exist; this is idempotent and has no runtime grant.
select public.bootstrap_legacy_practitioner_iam();

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
  ),
  (
    '70000000-0000-0000-0000-000000000003',
    'LOCAL-0003',
    'Sofía',
    'Muñoz',
    '1946-03-12',
    '10.000.003-0',
    'UCI adulto',
    'Cama 03',
    '{}'::jsonb
  ),
  (
    '70000000-0000-0000-0000-000000000004',
    'LOCAL-0004',
    'Tomás',
    'Álvarez',
    '2018-09-24',
    '7.000.004-K',
    'Pediatría',
    'Cuna 04',
    '{}'::jsonb
  ),
  (
    '70000000-0000-0000-0000-000000000005',
    'LOCAL-0005',
    'María José',
    'del Río',
    '1991-12-08',
    null,
    'Urgencia',
    'Box 06',
    '{}'::jsonb
  ),
  (
    '70000000-0000-0000-0000-000000000006',
    'LOCAL-0006',
    'Benjamín',
    'Fuentes Contreras',
    '1963-07-30',
    '10.000.006-0',
    'Unidad de Cuidados Intermedios',
    'Cama 21',
    '{}'::jsonb
  ),
  (
    '70000000-0000-0000-0000-000000000007',
    null,
    'Nora',
    'Vidal',
    null,
    null,
    null,
    null,
    '{}'::jsonb
  ),
  (
    '70000000-0000-0000-0000-000000000008',
    'LOCAL-0008',
    'Óscar',
    'Ibáñez',
    '1955-01-19',
    '10.000.008-0',
    'Medicina interna',
    'Cama 14',
    '{}'::jsonb
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
  ),
  (
    '80000000-0000-0000-0000-000000000001',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '11111111-1111-1111-1111-111111111111',
    'document', now() - interval '3 days',
    '{"summary":"Informe clínico sintético incorporado a la ficha."}'::jsonb
  ),
  (
    '80000000-0000-0000-0000-000000000002',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '22222222-2222-2222-2222-222222222222',
    'condition', now() - interval '6 days',
    '{"summary":"Molestia leve controlada durante el turno de prueba."}'::jsonb
  ),
  (
    '80000000-0000-0000-0000-000000000003',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    '22222222-2222-2222-2222-222222222222',
    'observation', now() - interval '9 hours',
    '{"summary":"Control programado sin cambios relevantes."}'::jsonb
  ),
  (
    '80000000-0000-0000-0000-000000000004',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    '11111111-1111-1111-1111-111111111111',
    'procedure', now() - interval '2 days',
    '{"summary":"Procedimiento de prueba completado según planificación."}'::jsonb
  ),
  (
    '80000000-0000-0000-0000-000000000005',
    '70000000-0000-0000-0000-000000000003',
    '11111111-1111-1111-1111-111111111111',
    'encounter', now() - interval '45 minutes',
    '{"summary":"Evaluación de ingreso completada."}'::jsonb
  ),
  (
    '80000000-0000-0000-0000-000000000006',
    '70000000-0000-0000-0000-000000000003',
    '22222222-2222-2222-2222-222222222222',
    'observation', now() - interval '5 hours',
    '{"summary":"Parámetros de prueba revisados durante el turno."}'::jsonb
  ),
  (
    '80000000-0000-0000-0000-000000000007',
    '70000000-0000-0000-0000-000000000003',
    '11111111-1111-1111-1111-111111111111',
    'condition', now() - interval '1 day 6 hours',
    '{"summary":"Condición simulada estable bajo observación."}'::jsonb
  ),
  (
    '80000000-0000-0000-0000-000000000008',
    '70000000-0000-0000-0000-000000000003',
    '44444444-4444-4444-4444-444444444444',
    'document', now() - interval '7 days',
    '{"summary":"Documento sintético de referencia adjuntado al episodio."}'::jsonb
  ),
  (
    '80000000-0000-0000-0000-000000000009',
    '70000000-0000-0000-0000-000000000004',
    '22222222-2222-2222-2222-222222222222',
    'observation', now() - interval '90 minutes',
    '{"summary":"Control pediátrico de prueba registrado sin novedades."}'::jsonb
  ),
  (
    '80000000-0000-0000-0000-000000000010',
    '70000000-0000-0000-0000-000000000004',
    '11111111-1111-1111-1111-111111111111',
    'procedure', now() - interval '4 days',
    '{"summary":"Procedimiento simulado finalizado correctamente."}'::jsonb
  ),
  (
    '80000000-0000-0000-0000-000000000011',
    '70000000-0000-0000-0000-000000000005',
    '44444444-4444-4444-4444-444444444444',
    'encounter', now() - interval '4 hours',
    '{"summary":"Atención de prueba registrada en box de urgencia."}'::jsonb
  ),
  (
    '80000000-0000-0000-0000-000000000012',
    '70000000-0000-0000-0000-000000000005',
    '11111111-1111-1111-1111-111111111111',
    'document', now() - interval '2 days 3 hours',
    '{"summary":"Resumen sintético de atención incorporado al registro."}'::jsonb
  ),
  (
    '80000000-0000-0000-0000-000000000013',
    '70000000-0000-0000-0000-000000000006',
    '11111111-1111-1111-1111-111111111111',
    'condition', now() - interval '6 hours',
    '{"summary":"Se verificó tolerancia a la movilización asistida; este escenario es sintético y no representa una indicación clínica real."}'::jsonb
  ),
  (
    '80000000-0000-0000-0000-000000000014',
    '70000000-0000-0000-0000-000000000006',
    '22222222-2222-2222-2222-222222222222',
    'observation', now() - interval '14 days',
    '{"summary":"Observación histórica ficticia conservada para visualizar el timeline."}'::jsonb
  ),
  (
    '80000000-0000-0000-0000-000000000015',
    '70000000-0000-0000-0000-000000000007',
    '44444444-4444-4444-4444-444444444444',
    'encounter', now() - interval '12 hours',
    '{"summary":"Encuentro sintético con información demográfica incompleta."}'::jsonb
  )
on conflict (id) do nothing;

-- Apply only the versioned, UUID-explicit synthetic episode/event/assignment map.
select public.bootstrap_synthetic_hospitalization_fixtures();
