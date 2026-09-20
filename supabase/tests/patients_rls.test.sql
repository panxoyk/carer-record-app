begin;

create extension if not exists pgtap;

select plan(24);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
) values
  ('90000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls.physician@example.test', crypt('TestPassword123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('90000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls.nurse@example.test', crypt('TestPassword123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('90000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls.technician@example.test', crypt('TestPassword123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('90000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls.admin@example.test', crypt('TestPassword123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '');

insert into public.practitioners (id, display_name, role, status) values
  ('90000000-0000-0000-0000-000000000001', 'Test Physician', 'physician', 'active'),
  ('90000000-0000-0000-0000-000000000002', 'Test Nurse', 'nurse', 'active'),
  ('90000000-0000-0000-0000-000000000003', 'Test Technician', 'technician', 'active'),
  ('90000000-0000-0000-0000-000000000004', 'Test Administrator', 'administrator', 'active');

insert into public.patients (id, given_name, family_name) values
  ('90000000-0000-0000-0000-000000000101', 'Test', 'Patient');

insert into public.clinical_events (id, patient_id, recorded_by, kind, occurred_at, payload) values
  ('90000000-0000-0000-0000-000000000201', '90000000-0000-0000-0000-000000000101', '90000000-0000-0000-0000-000000000001', 'observation', now(), '{"summary":"Test event"}');

set local role anon;
select is(
  (select count(*) from public.patients),
  0::bigint,
  'an anonymous caller cannot read patients'
);
select is(
  (select count(*) from public.clinical_events),
  0::bigint,
  'an anonymous caller cannot read clinical events'
);

set local role authenticated;

-- A valid session without an application profile has no clinical access.
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000099', true);
select is(
  (select count(*) from public.patients),
  0::bigint,
  'an authenticated user without a profile cannot read patients'
);
select is(
  (select count(*) from public.clinical_events),
  0::bigint,
  'an authenticated user without a profile cannot read clinical events'
);

-- Every active care role may only read patient records.
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);
select is(
  (select count(*) from public.patients where id = '90000000-0000-0000-0000-000000000101'),
  1::bigint,
  'an active physician can read patients'
);
select throws_ok(
  $$insert into public.patients (given_name, family_name) values ('Test', 'Patient')$$,
  '42501',
  'new row violates row-level security policy for table "patients"',
  'a physician cannot create patients'
);
select is(
  (select count(*) from public.clinical_events where id = '90000000-0000-0000-0000-000000000201'),
  1::bigint,
  'an active physician can read patient clinical events'
);
select throws_ok(
  $$insert into public.clinical_events (patient_id, kind, occurred_at, payload) values ('90000000-0000-0000-0000-000000000101', 'observation', now(), '{"summary":"test"}')$$,
  '42501',
  'new row violates row-level security policy for table "clinical_events"',
  'a physician cannot create clinical events'
);

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000002', true);
select is(
  (select count(*) from public.patients where id = '90000000-0000-0000-0000-000000000101'),
  1::bigint,
  'an active nurse can read patients'
);
select is(
  (select count(*) from public.clinical_events where id = '90000000-0000-0000-0000-000000000201'),
  1::bigint,
  'an active nurse can read clinical events'
);

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000003', true);
select is(
  (select count(*) from public.patients where id = '90000000-0000-0000-0000-000000000101'),
  1::bigint,
  'an active technician can read patients'
);
select is(
  (select count(*) from public.clinical_events where id = '90000000-0000-0000-0000-000000000201'),
  1::bigint,
  'an active technician can read clinical events'
);

-- Administrative authority is intentionally separate from clinical authority.
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000004', true);
select is(
  (select count(*) from public.patients where id = '90000000-0000-0000-0000-000000000101'),
  0::bigint,
  'an administrator has no implicit clinical patient access'
);
select is(
  (select count(*) from public.clinical_events where id = '90000000-0000-0000-0000-000000000201'),
  0::bigint,
  'an administrator has no implicit clinical event access'
);

update public.practitioners
set status = 'suspended'
where id = '90000000-0000-0000-0000-000000000001';
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);
select is(
  (select count(*) from public.patients where id = '90000000-0000-0000-0000-000000000101'),
  0::bigint,
  'a suspended physician cannot read patients'
);
select is(
  (select count(*) from public.clinical_events where id = '90000000-0000-0000-0000-000000000201'),
  0::bigint,
  'a suspended physician cannot read clinical events'
);

-- Active care roles retain read-only access.
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000002', true);
select lives_ok(
  $$update public.patients set given_name = 'Changed' where id = '90000000-0000-0000-0000-000000000101'$$,
  'a care practitioner cannot update patients'
);
select is(
  (select given_name from public.patients where id = '90000000-0000-0000-0000-000000000101'),
  'Test',
  'a denied patient update leaves the record unchanged'
);
select lives_ok(
  $$delete from public.patients where id = '90000000-0000-0000-0000-000000000101'$$,
  'a care practitioner cannot delete patients'
);
select is(
  (select count(*) from public.patients where id = '90000000-0000-0000-0000-000000000101'),
  1::bigint,
  'a denied patient delete leaves the record available'
);
select lives_ok(
  $$update public.clinical_events set kind = 'condition' where id = '90000000-0000-0000-0000-000000000201'$$,
  'a care practitioner cannot update clinical events'
);
select is(
  (select kind::text from public.clinical_events where id = '90000000-0000-0000-0000-000000000201'),
  'observation',
  'a denied clinical-event update leaves the event unchanged'
);
select lives_ok(
  $$delete from public.clinical_events where id = '90000000-0000-0000-0000-000000000201'$$,
  'a care practitioner cannot delete clinical events'
);
select is(
  (select count(*) from public.clinical_events where id = '90000000-0000-0000-0000-000000000201'),
  1::bigint,
  'a denied clinical-event delete leaves the event available'
);

select * from finish();
rollback;
