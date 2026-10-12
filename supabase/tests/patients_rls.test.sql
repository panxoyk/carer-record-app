begin;
create extension if not exists pgtap;
select plan(8);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
) values
  ('90000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls.physician@example.test', crypt('TestPassword123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '');
insert into public.practitioners (id, display_name, role, status)
values ('90000000-0000-0000-0000-000000000001', 'Synthetic test physician', 'physician', 'active');
insert into public.patients (id, given_name, family_name)
values ('90000000-0000-0000-0000-000000000101', 'Synthetic', 'Unlinked');
insert into public.clinical_events (id, patient_id, recorded_by, kind, occurred_at, payload)
values ('90000000-0000-0000-0000-000000000201', '90000000-0000-0000-0000-000000000101', '90000000-0000-0000-0000-000000000001', 'observation', now(), '{"summary":"Synthetic unlinked event"}');

set local role anon;
select throws_ok($$select * from public.patients$$,'42501',null,'anonymous caller has no patient SELECT privilege');
select throws_ok($$select * from public.clinical_events$$,'42501',null,'anonymous caller has no event SELECT privilege');

set local role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-000000000099',true);
select is((select count(*) from public.patients),0::bigint,'user without profile has no clinical access');
select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-000000000001',true);
select is((select count(*) from public.patients),0::bigint,'clinician cannot read an unlinked patient');
select is((select count(*) from public.clinical_events),0::bigint,'clinician cannot read an unlinked event');
select throws_ok($$select rut from public.patients$$,'42501',null,'RUT is unavailable by column privilege');
select throws_ok($$select payload from public.clinical_events$$,'42501',null,'raw payload is unavailable by column privilege');
select throws_ok($$insert into public.clinical_events(patient_id,kind,occurred_at,payload) values ('90000000-0000-0000-0000-000000000101','observation',now(),'{}')$$,'42501',null,'clinical writes are unavailable');

select * from finish();
rollback;
