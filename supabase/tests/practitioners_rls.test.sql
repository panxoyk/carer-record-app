begin;

create extension if not exists pgtap;

select plan(10);

-- A non-administrator sees only their own practitioner profile.
set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
select is(
  (select count(*) from public.practitioners),
  1::bigint,
  'a practitioner can read only their own profile'
);
select is(
  (select display_name from public.practitioners),
  'Dra. Ana Torres',
  'the practitioner profile belongs to the authenticated user'
);
select lives_ok(
  $$update public.practitioners set role = 'administrator' where id = '11111111-1111-1111-1111-111111111111'$$,
  'a denied update completes without changing a row'
);
select is(
  (select role::text from public.practitioners where id = '11111111-1111-1111-1111-111111111111'),
  'physician',
  'a non-administrator cannot change their role'
);
select throws_ok(
  $$select * from public.patients$$,
  '42501',
  'permission denied for table patients',
  'clinical patient data is not available to authenticated users'
);
select throws_ok(
  $$select * from public.clinical_events$$,
  '42501',
  'permission denied for table clinical_events',
  'clinical events are not available to authenticated users'
);

-- An active administrator can list and update practitioners.
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
select is(
  (select count(*) from public.practitioners),
  3::bigint,
  'an active administrator can list practitioners'
);
select lives_ok(
  $$update public.practitioners set status = 'suspended' where id = '22222222-2222-2222-2222-222222222222'$$,
  'an active administrator can suspend a practitioner'
);
select is(
  (select status::text from public.practitioners where id = '22222222-2222-2222-2222-222222222222'),
  'suspended',
  'the administrator update is visible'
);

-- Suspending an administrator removes their elevated list access.
update public.practitioners set status = 'suspended' where id = '33333333-3333-3333-3333-333333333333';
select is(
  (select count(*) from public.practitioners),
  1::bigint,
  'a suspended administrator no longer has administrative list access'
);

select * from finish();
rollback;
