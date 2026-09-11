begin;

create extension if not exists pgtap;

select plan(12);

set local role authenticated;

-- Every active care role may only read patient records.
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
select is(
  (select count(*) from public.patients),
  2::bigint,
  'an active physician can read patients'
);
select throws_ok(
  $$insert into public.patients (given_name, family_name) values ('Test', 'Patient')$$,
  '42501',
  'new row violates row-level security policy for table "patients"',
  'a physician cannot create patients'
);
select is(
  (select count(*) from public.clinical_events),
  3::bigint,
  'an active physician can read patient clinical events'
);
select throws_ok(
  $$insert into public.clinical_events (patient_id, kind, occurred_at, payload) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'observation', now(), '{"summary":"test"}')$$,
  '42501',
  'new row violates row-level security policy for table "clinical_events"',
  'a physician cannot create clinical events'
);

select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
select is(
  (select count(*) from public.patients),
  2::bigint,
  'an active nurse can read patients'
);
select is(
  (select count(*) from public.clinical_events),
  3::bigint,
  'an active nurse can read clinical events'
);

select set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', true);
select is(
  (select count(*) from public.patients),
  2::bigint,
  'an active technician can read patients'
);
select is(
  (select count(*) from public.clinical_events),
  3::bigint,
  'an active technician can read clinical events'
);

-- Administrative authority is intentionally separate from clinical authority.
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
select is(
  (select count(*) from public.patients),
  0::bigint,
  'an administrator has no implicit clinical patient access'
);
select is(
  (select count(*) from public.clinical_events),
  0::bigint,
  'an administrator has no implicit clinical event access'
);

update public.practitioners
set status = 'suspended'
where id = '11111111-1111-1111-1111-111111111111';
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
select is(
  (select count(*) from public.patients),
  0::bigint,
  'a suspended physician cannot read patients'
);
select is(
  (select count(*) from public.clinical_events),
  0::bigint,
  'a suspended physician cannot read clinical events'
);

select * from finish();
rollback;
