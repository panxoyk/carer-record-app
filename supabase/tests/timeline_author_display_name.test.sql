begin;
create extension if not exists pgtap;
select plan(15);

-- This file owns every fixture it uses. No demo patient, profile, or episode is
-- read from the seed; the transaction rolls the complete fixture back.
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
) values
  ('d4000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','timeline-author@example.test','',now(),'{}','{}',now(),now(),'','','',''),
  ('d4000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','timeline-reader-a@example.test','',now(),'{}','{}',now(),now(),'','','',''),
  ('d4000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','timeline-reader-b@example.test','',now(),'{}','{}',now(),now(),'','','',''),
  ('d4000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','timeline-no-permission@example.test','',now(),'{}','{}',now(),now(),'','','','');

insert into public.organizations (id, slug, display_name)
values ('d4100000-0000-0000-0000-000000000001','timeline-author-test','Timeline author test');
insert into public.profiles (id, auth_user_id, display_name, status) values
  ('d4200000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001','Synthetic author','active'),
  ('d4200000-0000-0000-0000-000000000002','d4000000-0000-0000-0000-000000000002','Synthetic reader A','active'),
  ('d4200000-0000-0000-0000-000000000003','d4000000-0000-0000-0000-000000000003','Synthetic reader B','active'),
  ('d4200000-0000-0000-0000-000000000004','d4000000-0000-0000-0000-000000000004','No-permission reader','active');
insert into public.organization_memberships (id, organization_id, profile_id, status) values
  ('d4300000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000001','d4200000-0000-0000-0000-000000000001','active'),
  ('d4300000-0000-0000-0000-000000000002','d4100000-0000-0000-0000-000000000001','d4200000-0000-0000-0000-000000000002','active'),
  ('d4300000-0000-0000-0000-000000000003','d4100000-0000-0000-0000-000000000001','d4200000-0000-0000-0000-000000000003','active'),
  ('d4300000-0000-0000-0000-000000000004','d4100000-0000-0000-0000-000000000001','d4200000-0000-0000-0000-000000000004','active');
insert into public.roles (id, organization_id, name, description) values
  ('d4400000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000001','Timeline reader','Synthetic test reader');
insert into public.role_permissions (organization_id, role_id, permission_code) values
  ('d4100000-0000-0000-0000-000000000001','d4400000-0000-0000-0000-000000000001','clinical.assigned.read'),
  ('d4100000-0000-0000-0000-000000000001','d4400000-0000-0000-0000-000000000001','clinical.timeline.read'),
  ('d4100000-0000-0000-0000-000000000001','d4400000-0000-0000-0000-000000000001','context.note.read');
alter table public.role_assignments disable trigger role_assignments_require_active_authority;
insert into public.role_assignments (id, organization_id, membership_id, role_id, valid_from) values
  ('d4500000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000001','d4300000-0000-0000-0000-000000000001','d4400000-0000-0000-0000-000000000001',now()-interval '1 day'),
  ('d4500000-0000-0000-0000-000000000002','d4100000-0000-0000-0000-000000000001','d4300000-0000-0000-0000-000000000002','d4400000-0000-0000-0000-000000000001',now()-interval '1 day'),
  ('d4500000-0000-0000-0000-000000000003','d4100000-0000-0000-0000-000000000001','d4300000-0000-0000-0000-000000000003','d4400000-0000-0000-0000-000000000001',now()-interval '1 day');
alter table public.role_assignments enable trigger role_assignments_require_active_authority;

insert into public.patients (id, organization_id, given_name, family_name)
values ('d4600000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000001','Synthetic','Patient');
insert into public.hospitalizations (id, organization_id, patient_id, status, admitted_at)
values ('d4700000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000001','d4600000-0000-0000-0000-000000000001','admitted',now());
insert into public.care_assignments (
  id, organization_id, hospitalization_id, membership_id, valid_from, created_by_membership_id
) values
  ('d4800000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000001','d4700000-0000-0000-0000-000000000001','d4300000-0000-0000-0000-000000000001',now()-interval '1 day','d4300000-0000-0000-0000-000000000001'),
  ('d4800000-0000-0000-0000-000000000002','d4100000-0000-0000-0000-000000000001','d4700000-0000-0000-0000-000000000001','d4300000-0000-0000-0000-000000000002',now()-interval '1 day','d4300000-0000-0000-0000-000000000001'),
  ('d4800000-0000-0000-0000-000000000003','d4100000-0000-0000-0000-000000000001','d4700000-0000-0000-0000-000000000001','d4300000-0000-0000-0000-000000000003',now()-interval '1 day','d4300000-0000-0000-0000-000000000001');

insert into public.context_notes (
  id, organization_id, hospitalization_id, patient_id, author_id, status,
  input_method, content, client_event_id
) values
  ('d4900000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000001','d4700000-0000-0000-0000-000000000001','d4600000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000001','confirmed','text','Synthetic authored milestone','d4910000-0000-0000-0000-000000000001'),
  ('d4900000-0000-0000-0000-000000000002','d4100000-0000-0000-0000-000000000001','d4700000-0000-0000-0000-000000000001','d4600000-0000-0000-0000-000000000001','d4a00000-0000-0000-0000-000000000099','confirmed','text','Synthetic milestone with no profile','d4910000-0000-0000-0000-000000000002');
insert into public.clinical_events (id, patient_id, organization_id, hospitalization_id, kind, occurred_at, payload)
values ('d4b00000-0000-0000-0000-000000000001','d4600000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000001','d4700000-0000-0000-0000-000000000001','observation',now(),'{"summary":"Synthetic clinical event"}');

select ok(has_function_privilege('authenticated','private.context_note_timeline_author_name(uuid,uuid,uuid)','execute')
  and not has_function_privilege('anon','private.context_note_timeline_author_name(uuid,uuid,uuid)','execute')
  and not has_function_privilege('service_role','private.context_note_timeline_author_name(uuid,uuid,uuid)','execute')
  and not exists (select 1 from aclexplode((select proacl from pg_proc
    where oid='private.context_note_timeline_author_name(uuid,uuid,uuid)'::regprocedure)) a
    where a.grantee=0 and a.privilege_type='EXECUTE'),
  'helper execution is limited to authenticated callers');
select ok(not has_column_privilege('authenticated','public.profiles','auth_user_id','select'),
  'authenticated cannot select the profile Auth identity key');
select is((select array_agg(column_name order by ordinal_position)::text
  from information_schema.columns where table_schema='public'
    and table_name='clinical_timeline_by_hospitalization'),
  '{organization_id,hospitalization_id,event_id,kind,occurred_at,summary,patient_id,created_at,source_kind,author_display_name}',
  'timeline exposes the contracted author name but no UUID/email column');
select ok((select reloptions @> array['security_invoker=true','security_barrier=true']
  from pg_class where oid='public.clinical_timeline_by_hospitalization'::regclass),
  'timeline retains invoker and barrier security');

update public.profiles set status='suspended'
where auth_user_id='d4000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','d4000000-0000-0000-0000-000000000002',true);
select is((select author_display_name from public.clinical_timeline_by_hospitalization
  where event_id='d4900000-0000-0000-0000-000000000001'),
  'Synthetic author'::text, 'authorized assigned reader resolves suspended/inactive author name');
select is((select author_display_name from public.clinical_timeline_by_hospitalization
  where event_id='d4900000-0000-0000-0000-000000000002'),
  null::text, 'missing author profile yields null without hiding the note');
select is((select author_display_name from public.clinical_timeline_by_hospitalization
  where event_id='d4b00000-0000-0000-0000-000000000001'),
  null::text, 'clinical event without a context-note author yields null');
select is(private.context_note_timeline_author_name(
    'd4900000-0000-0000-0000-000000000001',
    'd4100000-0000-0000-0000-000000000099',
    'd4700000-0000-0000-0000-000000000001'),
  null::text, 'helper rejects a mismatched tenant for the exact note');
select is(private.context_note_timeline_author_name(
    'd4900000-0000-0000-0000-000000000001',
    'd4100000-0000-0000-0000-000000000001',
    'd4700000-0000-0000-0000-000000000099'),
  null::text, 'helper rejects a mismatched episode for the exact note');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','d4000000-0000-0000-0000-000000000003',true);
select is((select author_display_name from public.clinical_timeline_by_hospitalization
  where event_id='d4900000-0000-0000-0000-000000000001'),
  'Synthetic author'::text, 'a second assigned reader resolves the same author name');
reset role;

update public.profiles set status='suspended'
where auth_user_id='d4000000-0000-0000-0000-000000000003';
set local role authenticated;
select set_config('request.jwt.claim.sub','d4000000-0000-0000-0000-000000000003',true);
select is((select count(*) from public.clinical_timeline_by_hospitalization
  where hospitalization_id='d4700000-0000-0000-0000-000000000001'),
  0::bigint, 'suspended profile cannot read timeline or resolve names');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','d4000000-0000-0000-0000-000000000004',true);
select is((select count(*) from public.clinical_timeline_by_hospitalization
  where hospitalization_id='d4700000-0000-0000-0000-000000000001'),
  0::bigint, 'member without role permissions cannot read timeline or names');
select is(private.context_note_timeline_author_name(
    'd4900000-0000-0000-0000-000000000001',
    'd4100000-0000-0000-0000-000000000001',
    'd4700000-0000-0000-0000-000000000001'),
  null::text, 'member without context-note permission cannot call through authorization');
reset role;

update public.care_assignments set revoked_at=now(), revoked_by_membership_id='d4300000-0000-0000-0000-000000000001'
where id='d4800000-0000-0000-0000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub','d4000000-0000-0000-0000-000000000002',true);
select is((select count(*) from public.clinical_timeline_by_hospitalization
  where hospitalization_id='d4700000-0000-0000-0000-000000000001'),
  0::bigint, 'revoked care assignment immediately removes timeline and author names');
select is(private.context_note_timeline_author_name(
    'd4900000-0000-0000-0000-000000000001',
    'd4100000-0000-0000-0000-000000000001',
    'd4700000-0000-0000-0000-000000000001'),
  null::text, 'revoked care assignment denies direct helper lookup');
reset role;

select * from finish();
rollback;
