begin;

create extension if not exists pgtap;

select plan(9);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
) values
  ('91000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'practitioners.physician@example.test', crypt('TestPassword123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('91000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'practitioners.nurse@example.test', crypt('TestPassword123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('91000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'practitioners.admin@example.test', crypt('TestPassword123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '');

insert into public.practitioners (id, display_name, role, status) values
  ('91000000-0000-0000-0000-000000000001', 'Test Physician', 'physician', 'active'),
  ('91000000-0000-0000-0000-000000000002', 'Test Nurse', 'nurse', 'active'),
  ('91000000-0000-0000-0000-000000000003', 'Test Administrator', 'administrator', 'active');

insert into public.patients (id, given_name, family_name) values
  ('91000000-0000-0000-0000-000000000101', 'Test', 'Patient');

insert into public.clinical_events (id, patient_id, recorded_by, kind, occurred_at, payload) values
  ('91000000-0000-0000-0000-000000000201', '91000000-0000-0000-0000-000000000101', '91000000-0000-0000-0000-000000000001', 'observation', now(), '{"summary":"Test event"}');

-- A non-administrator sees only their own practitioner profile.
set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
select is(
  (select count(*) from public.practitioners),
  1::bigint,
  'a practitioner can read only their own profile'
);
select is(
  (select display_name from public.practitioners),
  'Test Physician',
  'the practitioner profile belongs to the authenticated user'
);
select lives_ok(
  $$update public.practitioners set role = 'administrator' where id = '91000000-0000-0000-0000-000000000001'$$,
  'a denied update completes without changing a row'
);
select is(
  (select role::text from public.practitioners where id = '91000000-0000-0000-0000-000000000001'),
  'physician',
  'a non-administrator cannot change their role'
);
select is(
  (select count(*) from public.clinical_events where id = '91000000-0000-0000-0000-000000000201'),
  1::bigint,
  'an active care practitioner can read clinical events'
);

-- An active administrator can list and update practitioners.
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000003', true);
select is(
  (
    select count(*) from public.practitioners
    where id in (
      '91000000-0000-0000-0000-000000000001',
      '91000000-0000-0000-0000-000000000002',
      '91000000-0000-0000-0000-000000000003'
    )
  ),
  3::bigint,
  'an active administrator can list practitioners'
);
select lives_ok(
  $$update public.practitioners set status = 'suspended' where id = '91000000-0000-0000-0000-000000000002'$$,
  'an active administrator can suspend a practitioner'
);
select is(
  (select status::text from public.practitioners where id = '91000000-0000-0000-0000-000000000002'),
  'suspended',
  'the administrator update is visible'
);

-- Suspending an administrator removes their elevated list access.
update public.practitioners set status = 'suspended' where id = '91000000-0000-0000-0000-000000000003';
select is(
  (
    select count(*) from public.practitioners
    where id in (
      '91000000-0000-0000-0000-000000000001',
      '91000000-0000-0000-0000-000000000002',
      '91000000-0000-0000-0000-000000000003'
    )
  ),
  1::bigint,
  'a suspended administrator no longer has administrative list access'
);

select * from finish();
rollback;
