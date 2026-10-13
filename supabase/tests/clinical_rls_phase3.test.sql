begin;
create extension if not exists pgtap;
select plan(58);

select ok(not exists (
  select 1 from pg_policies where schemaname='public'
    and tablename in ('patients','clinical_events')
    and policyname in ('active care roles read patients','active care roles read clinical events')
), 'legacy clinical policies are absent');
select ok(to_regprocedure('public.can_read_patients()') is null
  and to_regprocedure('public.can_read_clinical_events()') is null,
  'legacy clinical helpers are absent');
select ok((select reloptions @> array['security_invoker=true','security_barrier=true']
  from pg_class where oid='public.clinical_census_by_hospitalization'::regclass),
  'census view is invoker-security and barrier');
select ok((select reloptions @> array['security_invoker=true','security_barrier=true']
  from pg_class where oid='public.clinical_patient_demographics_by_hospitalization'::regclass),
  'demographics view is invoker-security and barrier');
select ok((select reloptions @> array['security_invoker=true','security_barrier=true']
  from pg_class where oid='public.clinical_timeline_by_hospitalization'::regclass),
  'timeline view is invoker-security and barrier');
select ok(not has_table_privilege('anon','public.clinical_timeline_by_hospitalization','select'),
  'anon cannot select the views');
select ok(not has_column_privilege('authenticated','public.patients','rut','select')
  and not has_column_privilege('authenticated','public.patients','payload','select')
  and not has_column_privilege('authenticated','public.patients','external_reference','select'),
  'sensitive patient columns are not selectable');
select ok(not has_column_privilege('authenticated','public.clinical_events','payload','select')
  and not has_column_privilege('authenticated','public.clinical_events','recorded_by','select'),
  'sensitive event columns are not selectable');
select ok(not exists (
  select 1 from information_schema.columns
  where table_schema='public'
    and table_name in ('clinical_census_by_hospitalization',
      'clinical_patient_demographics_by_hospitalization','clinical_timeline_by_hospitalization')
    and column_name in ('rut','payload','external_reference','auth_user_id','recorded_by')
), 'clinical views omit sensitive and identity columns');
select ok(not has_table_privilege('authenticated','public.patients','insert')
  and not has_table_privilege('authenticated','public.patients','update')
  and not has_table_privilege('authenticated','public.patients','delete')
  and not has_table_privilege('authenticated','public.clinical_events','insert')
  and not has_table_privilege('authenticated','public.clinical_events','update')
  and not has_table_privilege('authenticated','public.clinical_events','delete'),
   'clinical DML remains unavailable');
select ok((select bool_and(not has_table_privilege(role_name, table_name, action))
  from unnest(array['authenticated','service_role']) role_name
  cross join unnest(array['public.patients','public.clinical_events']) table_name
  cross join unnest(array['insert','update','delete','truncate']) action),
  'authenticated and service_role have no clinical DML privileges');
select is((select array_agg(column_name order by ordinal_position)::text
  from information_schema.columns where table_schema='public'
    and table_name='clinical_census_by_hospitalization'),
  '{organization_id,hospitalization_id,patient_id,hospitalization_status,admitted_at,discharged_at,unit_id,bed_label,given_name,family_name,birth_date}',
  'census exposes exactly the contracted episode and demographic columns');
select is((select array_agg(column_name order by ordinal_position)::text
  from information_schema.columns where table_schema='public'
    and table_name='clinical_timeline_by_hospitalization'),
  '{organization_id,hospitalization_id,event_id,kind,occurred_at,summary,patient_id,created_at,source_kind}',
  'timeline exposes exactly the contracted event and milestone columns');
select ok(not has_column_privilege('authenticated','public.clinical_events','recorded_by','select')
  and not has_column_privilege('authenticated','public.clinical_events','payload','select'),
  'timeline source provenance and raw payload remain unavailable');

create function public.phase3_test_clinical_bridge()
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.clinical_events set summary = summary
   where id = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
end $$;
grant execute on function public.phase3_test_clinical_bridge() to service_role;
set local role service_role;
select lives_ok('select public.phase3_test_clinical_bridge()',
  'a controlled owner SECURITY DEFINER bridge can perform clinical writes');
select throws_ok($$update public.clinical_events set summary=summary$$,'42501',null,
  'service_role cannot update clinical events directly');
select throws_ok($$delete from public.clinical_events$$,'42501',null,
  'service_role cannot delete clinical events directly');
select throws_ok($$insert into public.clinical_events (patient_id, kind, occurred_at, payload) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','observation',now(),'{}')$$,'42501',null,
  'service_role cannot insert clinical events directly');
select throws_ok($$insert into public.patients(given_name,family_name) values ('No','Write')$$,'42501',null,
  'service_role cannot insert patients directly');
select throws_ok($$update public.patients set given_name=given_name$$,'42501',null,
  'service_role cannot update patients directly');
select throws_ok($$delete from public.patients$$,'42501',null,
  'service_role cannot delete patients directly');
select throws_ok($$truncate table public.patients$$,'42501',null,
  'service_role cannot truncate patients');
select throws_ok($$truncate table public.clinical_events$$,'42501',null,
  'service_role cannot truncate clinical events');
reset role;
drop function public.phase3_test_clinical_bridge();

grant insert, update, delete, truncate on public.patients, public.clinical_events to service_role;
set local role service_role;
select throws_ok($$update public.patients set given_name=given_name$$,'42501',null,
  'the database guard rejects runtime UPDATE even if a grant is accidentally restored');
select throws_ok($$delete from public.clinical_events$$,'42501',null,
  'the database guard rejects runtime DELETE even if a grant is accidentally restored');
select throws_ok($$truncate table public.clinical_events$$,'42501',null,
  'the database guard rejects runtime TRUNCATE even if a grant is accidentally restored');
reset role;
revoke insert, update, delete, truncate on public.patients, public.clinical_events from service_role;

insert into public.organizations (id, slug, display_name) values
  ('b2000000-0000-0000-0000-000000000001','clinical-test-other','Clinical test other tenant');
insert into public.patients (id, organization_id, given_name, family_name) values
  ('b2000000-0000-0000-0000-000000000002','b2000000-0000-0000-0000-000000000001','Synthetic','Other Tenant');
insert into public.hospitalizations (id, organization_id, patient_id, status, admitted_at) values
  ('b2000000-0000-0000-0000-000000000003','b2000000-0000-0000-0000-000000000001',
   'b2000000-0000-0000-0000-000000000002','admitted',now());

set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select is((select count(*) from public.patients where id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),1::bigint,
  'assigned clinician sees patient with an accessible hospitalization');
select is((select count(*) from public.clinical_events where hospitalization_id='a1000000-0000-0000-0000-000000000001'),2::bigint,
  'assigned clinician sees events for the exact hospitalization');
select is((select count(*) from public.clinical_events where hospitalization_id='a1000000-0000-0000-0000-000000000002'),2::bigint,
  'the same patient second episode is visible only through its own assignment');
select is((select count(*) from public.clinical_timeline_by_hospitalization where hospitalization_id='a1000000-0000-0000-0000-000000000001'),2::bigint,
  'timeline contract returns typed summary');
select is((select count(*) from public.clinical_census_by_hospitalization
  where hospitalization_id='a1000000-0000-0000-0000-000000000001'
    and given_name is not null and family_name is not null and birth_date is not null),1::bigint,
  'assigned clinician with census and patient permissions sees episode demographics');
select is((select count(*) from public.clinical_timeline_by_hospitalization
  where hospitalization_id='a1000000-0000-0000-0000-000000000001'
    and patient_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and created_at is not null),2::bigint,
  'timeline includes patient_id and created_at');
select is((select count(*) from public.clinical_census_by_hospitalization
  where organization_id='b2000000-0000-0000-0000-000000000001'),0::bigint,
  'clinical census does not expose another tenant');
select is((select count(*) from public.clinical_events where organization_id is null or hospitalization_id is null),0::bigint,
  'unlinked events remain hidden');
select throws_ok($$select * from public.patients$$,'42501',null,
  'base patient SELECT * is blocked by column grants');
select throws_ok($$select * from public.clinical_events$$,'42501',null,
  'base event SELECT * is blocked by column grants');
select throws_ok($$insert into public.patients(given_name,family_name) values ('No','Write')$$,'42501',null,
  'clinical patient DML is denied');
select throws_ok($$update public.patients set given_name=given_name$$,'42501',null,
  'authenticated cannot update patients');
select throws_ok($$delete from public.patients$$,'42501',null,
  'authenticated cannot delete patients');
select throws_ok($$update public.clinical_events set summary=summary$$,'42501',null,
  'authenticated cannot update clinical events');
select throws_ok($$delete from public.clinical_events$$,'42501',null,
  'authenticated cannot delete clinical events');
select throws_ok($$insert into public.clinical_events (patient_id, kind, occurred_at, payload) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','observation',now(),'{}')$$,'42501',null,
  'authenticated cannot insert clinical events');
select throws_ok($$truncate table public.patients$$,'42501',null,
  'authenticated cannot truncate patients');
select throws_ok($$truncate table public.clinical_events$$,'42501',null,
  'authenticated cannot truncate clinical events');

reset role;
update public.care_assignments ca set valid_from=now()+interval '1 day'
where ca.hospitalization_id='a1000000-0000-0000-0000-000000000002'
  and ca.membership_id=(select m.id from public.organization_memberships m
    join public.profiles p on p.id=m.profile_id
    where p.auth_user_id='11111111-1111-1111-1111-111111111111');
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select is((select count(*) from public.clinical_events where hospitalization_id='a1000000-0000-0000-0000-000000000002'),0::bigint,
  'future assignment does not grant access');
reset role;
update public.care_assignments ca set valid_from=now()-interval '1 day', valid_until=now()-interval '1 second'
where ca.hospitalization_id='a1000000-0000-0000-0000-000000000002'
  and ca.membership_id=(select m.id from public.organization_memberships m
    join public.profiles p on p.id=m.profile_id
    where p.auth_user_id='11111111-1111-1111-1111-111111111111');
set local role authenticated;
select is((select count(*) from public.clinical_events where hospitalization_id='a1000000-0000-0000-0000-000000000002'),0::bigint,
  'expired assignment does not grant access');
reset role;
update public.care_assignments ca set valid_until=null, revoked_at=now()
where ca.hospitalization_id='a1000000-0000-0000-0000-000000000002'
  and ca.membership_id=(select m.id from public.organization_memberships m
    join public.profiles p on p.id=m.profile_id
    where p.auth_user_id='11111111-1111-1111-1111-111111111111');
set local role authenticated;
select is((select count(*) from public.clinical_events where hospitalization_id='a1000000-0000-0000-0000-000000000002'),0::bigint,
  'revoked assignment takes effect in the same open session');
select is((select count(*) from public.clinical_events where hospitalization_id='a1000000-0000-0000-0000-000000000001'),2::bigint,
  'revoking one episode assignment preserves access only to the other episode');
reset role;
update public.hospitalizations set status='cancelled'
where id='a1000000-0000-0000-0000-000000000001';
set local role authenticated;
select is((select count(*) from public.clinical_events where hospitalization_id='a1000000-0000-0000-0000-000000000001'),0::bigint,
  'cancelled hospitalization denies access');
reset role;
update public.hospitalizations set status='entered_in_error'
where id='a1000000-0000-0000-0000-000000000003';
set local role authenticated;
select set_config('request.jwt.claim.sub','22222222-2222-2222-2222-222222222222',true);
select is((select count(*) from public.clinical_events where hospitalization_id='a1000000-0000-0000-0000-000000000003'),0::bigint,
  'entered-in-error hospitalization denies access');

reset role;
update public.profiles set status='suspended' where auth_user_id='11111111-1111-1111-1111-111111111111';
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select is((select count(*) from public.clinical_events where hospitalization_id='a1000000-0000-0000-0000-000000000004'),0::bigint,
  'suspended profile denies access');
reset role;
update public.profiles set status='active' where auth_user_id='11111111-1111-1111-1111-111111111111';
update public.organization_memberships m set status='suspended'
from public.profiles p where p.id=m.profile_id and p.auth_user_id='11111111-1111-1111-1111-111111111111';
set local role authenticated;
select is((select count(*) from public.clinical_events where hospitalization_id='a1000000-0000-0000-0000-000000000004'),0::bigint,
  'suspended membership denies access');
reset role;
update public.organization_memberships m set status='active'
from public.profiles p where p.id=m.profile_id and p.auth_user_id='11111111-1111-1111-1111-111111111111';
update public.roles set status='inactive' where name='Personal clínico';
set local role authenticated;
select is((select count(*) from public.clinical_events where hospitalization_id='a1000000-0000-0000-0000-000000000004'),0::bigint,
  'inactive role denies access');
reset role;
update public.roles set status='active' where name='Personal clínico';

set local role authenticated;
select set_config('request.jwt.claim.sub','44444444-4444-4444-4444-444444444444',true);
select is((select count(*) from public.patients),0::bigint,
  'legacy technician role has no clinical access');

reset role;
delete from public.role_permissions rp using public.roles r
where r.id=rp.role_id and r.protected_kind='demo_administrator'
  and rp.permission_code='clinical.organization.read';
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-3333-3333-333333333333',true);
select is((select count(*) from public.clinical_census_by_hospitalization),0::bigint,
  'administrator without reserved organization permission has no census access');
reset role;
insert into public.role_permissions (organization_id,role_id,permission_code)
select organization_id,id,'clinical.organization.read' from public.roles
where protected_kind='demo_administrator';
delete from public.role_permissions rp using public.roles r
where r.id=rp.role_id and r.protected_kind='demo_administrator'
  and rp.permission_code='clinical.timeline.read';
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-3333-3333-333333333333',true);
select is((select count(*) from public.clinical_timeline_by_hospitalization),0::bigint,
  'administrator without concrete timeline permission has no timeline access');
reset role;
insert into public.role_permissions (organization_id,role_id,permission_code)
select organization_id,id,'clinical.timeline.read' from public.roles
where protected_kind='demo_administrator';
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-3333-3333-333333333333',true);
select ok((select count(*) > 0 from public.clinical_census_by_hospitalization),
  'administrator sees tenant census with reserved and concrete permissions');
reset role;
delete from public.role_permissions rp using public.roles r
where r.id=rp.role_id and r.protected_kind='demo_administrator'
  and rp.permission_code='clinical.patient.read';
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-3333-3333-333333333333',true);
select is((select count(*) from public.clinical_census_by_hospitalization),0::bigint,
  'census demographics require both census.read and patient.read');
reset role;
insert into public.role_permissions (organization_id,role_id,permission_code)
select organization_id,id,'clinical.patient.read' from public.roles
where protected_kind='demo_administrator';

select * from finish();
rollback;
