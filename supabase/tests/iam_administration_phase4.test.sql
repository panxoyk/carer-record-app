begin;
create extension if not exists pgtap;
select plan(58);
select public.bootstrap_synthetic_hospitalization_fixtures();
update public.permission_catalog set status='deprecated',deprecated_at=now() where code='clinical.timeline.read';

create function public.phase4_org() returns uuid language sql security definer set search_path='' as $$
 select id from public.organizations where slug='demo-hospital'
$$;
create function public.phase4_member(uuid) returns uuid language sql security definer set search_path='' as $$
 select m.id from public.organization_memberships m join public.profiles p on p.id=m.profile_id where p.auth_user_id=$1 and m.organization_id=public.phase4_org()
$$;
create function public.phase4_assignment(text,uuid default null) returns uuid language sql security definer set search_path='' as $$
 select ra.id from public.role_assignments ra join public.roles r on r.id=ra.role_id
 join public.organization_memberships m on m.id=ra.membership_id join public.profiles p on p.id=m.profile_id
 where r.organization_id=public.phase4_org() and (r.name=$1 or r.protected_kind=$1)
 and ($2 is null or p.auth_user_id=$2) order by ra.created_at limit 1
$$;
create function public.phase4_role(text) returns uuid language sql security definer set search_path='' as $$
 select id from public.roles where organization_id=public.phase4_org() and name=$1
$$;
grant execute on function public.phase4_org(), public.phase4_member(uuid), public.phase4_assignment(text,uuid), public.phase4_role(text) to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-3333-3333-333333333333',true);
select is((select result_code from public.create_iam_role(public.phase4_org(),'Synthetic observer','Synthetic role','b9100000-0000-0000-0000-000000000001')),'created','authorized actor creates ordinary role');
select is((select result_code from public.create_iam_role(public.phase4_org(),'Name|with|pipes','Description|with|pipes','b9100000-0000-0000-0000-000000000020')),'created','role with pipes in both fields is created');
select ok((select name='Name|with|pipes' and description='Description|with|pipes' from public.roles where name='Name|with|pipes'),'role name and description retain pipes exactly');
select is((select result_code from public.update_iam_role(public.phase4_org(),(select id from public.roles where name='Name|with|pipes'),'Updated|name','Updated|description','b9100000-0000-0000-0000-000000000021')),'updated','role with pipe fields updates');
select ok((select name='Updated|name' and description='Updated|description' from public.roles where name='Updated|name'),'updated role fields retain pipes exactly');
select is((select result_code from public.create_iam_role(public.phase4_org(),'Synthetic observer','duplicate','b9100000-0000-0000-0000-000000000022')),'role_name_conflict','duplicate role name returns audited stable conflict');
select is((select result_code from public.update_iam_role(public.phase4_org(),(select id from public.roles where name='Updated|name'),'Synthetic observer','conflicting update','b9100000-0000-0000-0000-000000000023')),'role_name_conflict','duplicate role update returns stable conflict');
select is((select result_code from public.create_iam_role(public.phase4_org(),'Replay role','Replay role','b9100000-0000-0000-0000-000000000001')),'idempotency_conflict','different role payload conflicts');
select is((select result_code from public.create_iam_role('00000000-0000-0000-0000-000000000000','Cross tenant','Cross tenant','b9100000-0000-0000-0000-000000000014')),'denied','cross-tenant/unknown organization is opaque');
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select is((select result_code from public.create_iam_role(public.phase4_org(),'Unauthorized','Unauthorized','b9100000-0000-0000-0000-000000000015')),'denied','actor without role.manage is denied');
select set_config('request.jwt.claim.sub','33333333-3333-3333-3333-333333333333',true);
select is((select result_code from public.replace_iam_role_permissions(public.phase4_org(),(select id from public.roles where name='Synthetic observer'),array['clinical.census.read','clinical.patient.read'],'b9100000-0000-0000-0000-000000000002')),'permissions_replaced','ordinary catalogued permissions can be composed when actor possesses them');
select ok((select replayed and result_code='permissions_replaced' from public.replace_iam_role_permissions(public.phase4_org(),(select id from public.roles where name='Synthetic observer'),array['clinical.patient.read','clinical.census.read','clinical.census.read'],'b9100000-0000-0000-0000-000000000002')),'composition replay canonicalizes order and duplicate permissions');
select is((select result_code from public.replace_iam_role_permissions(public.phase4_org(),(select id from public.roles where name='Synthetic observer'),array['clinical.organization.read'],'b9100000-0000-0000-0000-000000000003')),'permission_not_delegable','system-only permission denied');
select is((select result_code from public.replace_iam_role_permissions(public.phase4_org(),(select id from public.roles where name='Synthetic observer'),array['clinical.patient.identifier.read'],'b9100000-0000-0000-0000-000000000004')),'permission_not_delegable','permission not effectively possessed by actor denied');
select is((select result_code from public.replace_iam_role_permissions(public.phase4_org(),(select id from public.roles where name='Synthetic observer'),array['clinical.timeline.read'],'b9100000-0000-0000-0000-000000000019')),'permission_not_delegable','deprecated permission cannot be composed');
select is((select result_code from public.replace_iam_role_permissions(public.phase4_org(),(select id from public.roles where name='Synthetic observer'),null,'b9100000-0000-0000-0000-000000000024')),'permission_not_delegable','null permission set is invalid');
select is((select result_code from public.replace_iam_role_permissions(public.phase4_org(),(select id from public.roles where name='Synthetic observer'),array[]::text[],'b9100000-0000-0000-0000-000000000024')),'idempotency_conflict','null and empty permission sets have distinct replay signatures');
select is((select result_code from public.replace_iam_role_permissions(public.phase4_org(),(select id from public.roles where protected_kind='demo_administrator'),array['clinical.census.read'],'b9100000-0000-0000-0000-000000000005')),'protected_or_missing','ordinary operation cannot edit protected role');
select is((select result_code from public.grant_iam_role(public.phase4_org(),public.phase4_member('22222222-2222-2222-2222-222222222222'),(select id from public.roles where name='Synthetic observer'),now(),null,'b9100000-0000-0000-0000-000000000006')),'granted','role grant succeeds');
select ok((select target_id is not null from public.grant_iam_role(public.phase4_org(),public.phase4_member('22222222-2222-2222-2222-222222222222'),(select id from public.roles where name='Synthetic observer'),now(),null,'b9100000-0000-0000-0000-000000000006')),'role grant returns stable assignment ID');
select is((select result_code from public.grant_iam_role(public.phase4_org(),public.phase4_member('33333333-3333-3333-3333-333333333333'),(select id from public.roles where name='Synthetic observer'),now(),null,'b9100000-0000-0000-0000-000000000007')),'invalid_request','self role assignment denied');
select is((select result_code from public.grant_iam_role(public.phase4_org(),public.phase4_member('22222222-2222-2222-2222-222222222222'),(select id from public.roles where name='Synthetic observer'),now(),null,'b9100000-0000-0000-0000-000000000006')),'granted','identical grant is stable replay');
select ok((select replayed from public.grant_iam_role(public.phase4_org(),public.phase4_member('22222222-2222-2222-2222-222222222222'),(select id from public.roles where name='Synthetic observer'),now(),null,'b9100000-0000-0000-0000-000000000006')),'grant replay identified');
select is((select result_code from public.grant_iam_role(public.phase4_org(),public.phase4_member('22222222-2222-2222-2222-222222222222'),(select id from public.roles where name='Synthetic observer'),now()+interval '1 day',null,'b9100000-0000-0000-0000-000000000006')),'idempotency_conflict','changed grant payload conflicts');
select is((select result_code from public.grant_iam_role(public.phase4_org(),public.phase4_member('22222222-2222-2222-2222-222222222222'),(select id from public.roles where name='Synthetic observer'),now(),null,'b9100000-0000-0000-0000-000000000016')),'overlap','overlapping role assignment denied');
select is((select result_code from public.grant_iam_role(public.phase4_org(),public.phase4_member('55555555-5555-5555-5555-555555555555'),(select id from public.roles where name='Synthetic observer'),now(),null,'b9100000-0000-0000-0000-000000000017')),'invalid_request','inactive membership cannot receive a role');

-- A clinician with role.assign but without assignment.manage cannot delegate that permission.
select is((select result_code from public.create_iam_role(public.phase4_org(),'Role assigner','Only role.assign','b9100000-0000-0000-0000-000000000025')),'created','delegation fixture role created');
select is((select result_code from public.replace_iam_role_permissions(public.phase4_org(),(select id from public.roles where name='Role assigner'),array['iam.role.assign'],'b9100000-0000-0000-0000-000000000026')),'permissions_replaced','assigner composition established');
select is((select result_code from public.grant_iam_role(public.phase4_org(),public.phase4_member('11111111-1111-1111-1111-111111111111'),(select id from public.roles where name='Role assigner'),now(),null,'b9100000-0000-0000-0000-000000000027')),'granted','role.assign granted to clinician actor');
select is((select result_code from public.create_iam_role(public.phase4_org(),'Needs assignment manage','Sensitive delegated permission','b9100000-0000-0000-0000-000000000028')),'created','sensitive target role created');
select is((select result_code from public.replace_iam_role_permissions(public.phase4_org(),(select id from public.roles where name='Needs assignment manage'),array['clinical.assignment.manage'],'b9100000-0000-0000-0000-000000000029')),'permissions_replaced','sensitive target role composition established');
select is((select result_code from public.create_iam_role(public.phase4_org(),'Delegable observer','Ordinary possessed permission','b9100000-0000-0000-0000-000000000030')),'created','delegable target role created');
select is((select result_code from public.replace_iam_role_permissions(public.phase4_org(),(select id from public.roles where name='Delegable observer'),array['clinical.census.read'],'b9100000-0000-0000-0000-000000000031')),'permissions_replaced','delegable target role composition established');
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select ok(public.has_active_iam_permission(public.phase4_org(),'iam.role.assign') and not public.has_active_iam_permission(public.phase4_org(),'clinical.assignment.manage'),'regression actor has assign but not assignment.manage');
select is((select result_code from public.grant_iam_role(public.phase4_org(),public.phase4_member('22222222-2222-2222-2222-222222222222'),public.phase4_role('Needs assignment manage'),now(),null,'b9100000-0000-0000-0000-000000000032')),'role_not_delegable','role.assign alone cannot delegate clinical.assignment.manage');
select is((select result_code from public.grant_iam_role(public.phase4_org(),public.phase4_member('22222222-2222-2222-2222-222222222222'),public.phase4_role('Delegable observer'),now(),null,'b9100000-0000-0000-0000-000000000033')),'granted','a delegable role can be granted by role.assign actor');
select set_config('request.jwt.claim.sub','33333333-3333-3333-3333-333333333333',true);
select is((select result_code from public.revoke_iam_role(public.phase4_org(),
 (select target_id from public.grant_iam_role(public.phase4_org(),public.phase4_member('22222222-2222-2222-2222-222222222222'),(select id from public.roles where name='Synthetic observer'),now(),null,'b9100000-0000-0000-0000-000000000006')),'b9100000-0000-0000-0000-000000000008')),'revoked','ordinary role grant revocable historically');
select is((select result_code from public.grant_iam_role(public.phase4_org(),public.phase4_member('22222222-2222-2222-2222-222222222222'),(select id from public.roles where name='Synthetic observer'),now(),null,'b9100000-0000-0000-0000-000000000018')),'granted','a later grant preserves prior revoked assignment history');
select is((select result_code from public.grant_iam_administrator(public.phase4_org(),public.phase4_member('33333333-3333-3333-3333-333333333333'),(select id from public.roles where protected_kind='demo_administrator'),now(),null,'b9100000-0000-0000-0000-000000000009')),'invalid_request','administrator cannot self-assign');
select is((select result_code from public.revoke_iam_administrator(public.phase4_org(),public.phase4_assignment('demo_administrator','33333333-3333-3333-3333-333333333333'),'b9100000-0000-0000-0000-000000000010')),'self_revocation_denied','sole administrator cannot revoke self');
select is((select result_code from public.manage_organization_membership(public.phase4_org(),public.phase4_member('33333333-3333-3333-3333-333333333333'),'suspended',null,'b9100000-0000-0000-0000-000000000011')),'last_administrator','last administrator suspension denied');
select is((select result_code from public.grant_iam_administrator(public.phase4_org(),public.phase4_member('11111111-1111-1111-1111-111111111111'),(select id from public.roles where protected_kind='demo_administrator'),now(),null,'b9100000-0000-0000-0000-000000000012')),'granted','second administrator grant succeeds');
select is((select result_code from public.revoke_iam_administrator(public.phase4_org(),public.phase4_assignment('demo_administrator','33333333-3333-3333-3333-333333333333'),'b9100000-0000-0000-0000-000000000034')),'self_revocation_denied','administrator cannot self-revoke even when a second administrator exists');
select is((select result_code from public.revoke_iam_administrator(public.phase4_org(),public.phase4_assignment('demo_administrator','11111111-1111-1111-1111-111111111111'),'b9100000-0000-0000-0000-000000000013')),'revoked','administrator may revoke another administrator');
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select ok((select result_code='denied' and target_id is null and not replayed from public.create_iam_role(public.phase4_org(),'Synthetic observer','Synthetic role','b9100000-0000-0000-0000-000000000001')),'actor without authority cannot inspect prior replay result');
select set_config('request.jwt.claim.sub','33333333-3333-3333-3333-333333333333',true);
select ok(not has_table_privilege('authenticated','public.roles','insert') and not has_table_privilege('service_role','public.roles','insert'),'runtime roles lack direct write grants');
select ok(not has_table_privilege('authenticated','public.organization_memberships','update') and not has_table_privilege('service_role','public.organization_memberships','truncate'),'membership DML and truncate denied');
select ok(not has_table_privilege('authenticated','public.role_permissions','delete') and not has_table_privilege('service_role','public.role_assignments','update'),'composition and grant DML denied');
select throws_ok($$truncate public.roles$$,'42501',null,'authenticated truncate guard blocks');
select throws_ok($$update public.roles set name='bypass'$$,'42501',null,'authenticated role update guard blocks');
reset role;
update public.permission_catalog set status='active',deprecated_at=null where code='clinical.timeline.read';
select ok((select count(*)=1 from public.role_permissions rp join public.roles r on r.id=rp.role_id
  where r.protected_kind='demo_administrator' and rp.permission_code='clinical.assigned.read'),'protected administrator receives assigned-read by migration');
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-3333-3333-333333333333',true);
select is((select result_code from public.grant_iam_role(public.phase4_org(),public.phase4_member('44444444-4444-4444-4444-444444444444'),public.phase4_role('Personal clínico'),now(),null,'b9100000-0000-0000-0000-000000000035')),'granted','administrator grants Personal clínico to another active membership');
select set_config('request.jwt.claim.sub','44444444-4444-4444-4444-444444444444',true);
select ok(public.has_active_iam_permission(public.phase4_org(),'clinical.assigned.read'),'granted clinician receives assigned-read permission');
select is((select count(*) from public.clinical_census_by_hospitalization),0::bigint,'assigned-read alone does not expose clinical rows without care assignments');
reset role;
set local role service_role;
select throws_ok($$truncate public.role_assignments$$,'42501',null,'service role truncate guard blocks');
select throws_ok($$delete from public.organization_memberships$$,'42501',null,'service role membership delete guard blocks');
reset role;
select ok((select count(*)=0 from public.audit_events where action like 'iam.%' and metadata::text ~* '(email|jwt|clinical_payload|given_name|family_name|Synthetic observer)'),'IAM audit is sanitized and excludes names');
select ok((select count(*)>0 from public.audit_events where action like 'iam.%' and result='denied'),'attributable IAM denials are audited');
select * from finish();
rollback;
