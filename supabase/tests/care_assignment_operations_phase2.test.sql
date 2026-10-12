begin;
create extension if not exists pgtap;
select plan(58);
select public.bootstrap_synthetic_hospitalization_fixtures();

-- A fresh episode with seeded synthetic patient, administered by the protected admin.
create function public.phase2_test_org() returns uuid language sql security definer set search_path='' as $$ select id from public.organizations where slug='demo-hospital' $$;
create function public.phase2_test_member(p_auth uuid) returns uuid language sql security definer set search_path='' as $$
  select m.id from public.organization_memberships m join public.profiles p on p.id=m.profile_id
  where p.auth_user_id=p_auth and m.organization_id=(select id from public.organizations where slug='demo-hospital')
$$;
grant execute on function public.phase2_test_org() to authenticated;
grant execute on function public.phase2_test_member(uuid) to authenticated;

insert into public.hospitalizations (id, organization_id, patient_id, status, admitted_at)
select 'a9000000-0000-0000-0000-000000000001', p.organization_id, p.id, 'admitted', now()
from public.patients p where p.id = '70000000-0000-0000-0000-000000000008';
insert into public.organizations (id, slug, display_name)
values ('a9300000-0000-0000-0000-000000000001', 'assignment-other-tenant', 'Synthetic other tenant');
insert into public.organization_memberships (id, organization_id, profile_id, status)
select 'a9400000-0000-0000-0000-000000000001', 'a9300000-0000-0000-0000-000000000001', profile.id, 'active'
from public.profiles profile where profile.auth_user_id='11111111-1111-1111-1111-111111111111';

set local role authenticated;
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
set local time zone 'America/Santiago';
select is((select result_code from public.grant_care_assignment(
  public.phase2_test_org(), 'a9000000-0000-0000-0000-000000000001',
  public.phase2_test_member('22222222-2222-2222-2222-222222222222'::uuid),
  '2026-10-01 00:00:00+00', null, 'a9100000-0000-0000-0000-000000000013')),
  'granted', 'first grant stores canonical absolute timestamp request');
set local time zone 'UTC';
select is((select result_code from public.grant_care_assignment(
  public.phase2_test_org(), 'a9000000-0000-0000-0000-000000000001',
  public.phase2_test_member('22222222-2222-2222-2222-222222222222'::uuid),
  '2026-10-01 00:00:00+00', null, 'a9100000-0000-0000-0000-000000000013')),
  'granted', 'replay across session time zones returns previous result');
select ok((select replayed from public.grant_care_assignment(
  public.phase2_test_org(), 'a9000000-0000-0000-0000-000000000001',
  public.phase2_test_member('22222222-2222-2222-2222-222222222222'::uuid),
  '2026-10-01 00:00:00+00', null, 'a9100000-0000-0000-0000-000000000013')),
  'timezone-independent replay reports replayed=true');
select is((select count(*)::int from public.care_assignments ca
  join public.audit_events ae on ae.target_id=ca.id
  where ca.hospitalization_id='a9000000-0000-0000-0000-000000000001'
    and ca.membership_id=public.phase2_test_member('22222222-2222-2222-2222-222222222222'::uuid)
    and ae.idempotency_key='a9100000-0000-0000-0000-000000000013'), 1,
  'timezone replay produces one assignment and one audit event');
reset role;
update public.organizations set status='suspended' where slug='demo-hospital';
set local role authenticated;
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
select is((select result_code || ':' || coalesce(assignment_id::text, 'null')
  from public.grant_care_assignment(
    public.phase2_test_org(), 'a9000000-0000-0000-0000-000000000001',
    public.phase2_test_member('22222222-2222-2222-2222-222222222222'::uuid),
    '2026-10-01 00:00:00+00', null, 'a9100000-0000-0000-0000-000000000013')),
  'denied:null', 'suspended organization hides prior grant replay and assignment id');
reset role;
select is((select (select count(*)::text from public.audit_events where idempotency_key='a9100000-0000-0000-0000-000000000013')
  || ':' || (select count(*)::text from public.care_assignments ca join public.audit_events ae on ae.target_id=ca.id
    where ae.idempotency_key='a9100000-0000-0000-0000-000000000013')),
  '1:1', 'unauthorized replay adds neither audit nor assignment effect');
update public.organizations set status='active' where slug='demo-hospital';
set local role authenticated;
select ok((select result_code='granted' and replayed and assignment_id is not null
  from public.grant_care_assignment(
    public.phase2_test_org(), 'a9000000-0000-0000-0000-000000000001',
    public.phase2_test_member('22222222-2222-2222-2222-222222222222'::uuid),
    '2026-10-01 00:00:00+00', null, 'a9100000-0000-0000-0000-000000000013')),
  'reactivated organization permits replay of prior grant');
set local time zone 'UTC';
select is((select result_code from public.grant_care_assignment(
  public.phase2_test_org(),
  'a9000000-0000-0000-0000-000000000001',
  public.phase2_test_member('11111111-1111-1111-1111-111111111111'::uuid),
  now()-interval '1 hour', null, 'a9100000-0000-0000-0000-000000000001')),
  'granted', 'authorized admin grants assignment');
select is((select count(*)::int from public.care_assignments where hospitalization_id='a9000000-0000-0000-0000-000000000001' and membership_id=public.phase2_test_member('11111111-1111-1111-1111-111111111111'::uuid)),1,'grant writes one row atomically');
select is((select result_code from public.grant_care_assignment(
  public.phase2_test_org(), 'a9000000-0000-0000-0000-000000000001',
  public.phase2_test_member('11111111-1111-1111-1111-111111111111'::uuid),
  now()-interval '1 hour', null, 'a9100000-0000-0000-0000-000000000001')),
  'granted', 'same request replays prior result');
select ok((select replayed from public.grant_care_assignment(
  public.phase2_test_org(), 'a9000000-0000-0000-0000-000000000001',
  public.phase2_test_member('11111111-1111-1111-1111-111111111111'::uuid),
  now()-interval '1 hour', null, 'a9100000-0000-0000-0000-000000000001')), 'same key returns replayed=true');
select is((select result_code from public.grant_care_assignment(
  public.phase2_test_org(), 'a9000000-0000-0000-0000-000000000001',
  public.phase2_test_member('11111111-1111-1111-1111-111111111111'::uuid),
  now()-interval '2 hours', null, 'a9100000-0000-0000-0000-000000000001')),
  'idempotency_conflict', 'same key with changed payload conflicts');

select is((select result_code from public.grant_care_assignment(
  public.phase2_test_org(), 'a9000000-0000-0000-0000-000000000001',
  public.phase2_test_member('11111111-1111-1111-1111-111111111111'::uuid),
  now(), null, 'a9100000-0000-0000-0000-000000000002')),
  'overlap', 'overlapping equivalent grant denied');
select is((select result_code from public.grant_care_assignment(
  public.phase2_test_org(), 'a9000000-0000-0000-0000-000000000001',
  public.phase2_test_member('44444444-4444-4444-4444-444444444444'::uuid),
  now(), null, 'a9100000-0000-0000-0000-000000000003')),
  'target_not_eligible', 'technician without clinical.assigned.read denied');
select is((select result_code from public.grant_care_assignment(
  public.phase2_test_org(), 'a9000000-0000-0000-0000-000000000001',
  public.phase2_test_member('55555555-5555-5555-5555-555555555555'::uuid),
  now(), null, 'a9100000-0000-0000-0000-000000000004')),
  'target_not_eligible', 'suspended target denied');
select is((select result_code from public.grant_care_assignment(
  public.phase2_test_org(), 'a9000000-0000-0000-0000-000000000001',
  'a9400000-0000-0000-0000-000000000001', now(), null, 'a9100000-0000-0000-0000-000000000011')),
  'target_not_eligible', 'membership from another tenant cannot be assigned');
select is((select result_code from public.grant_care_assignment(
  public.phase2_test_org(), 'a1000000-0000-0000-0000-000000000001',
  public.phase2_test_member('33333333-3333-3333-3333-333333333333'::uuid),
  now(), null, 'a9100000-0000-0000-0000-000000000005')),
  'self_assignment_denied', 'actor cannot self-assign');
select is((select result_code from public.grant_care_assignment(
  public.phase2_test_org(), 'a1000000-0000-0000-0000-000000000001',
  public.phase2_test_member('11111111-1111-1111-1111-111111111111'::uuid),
  now(), now(), 'a9100000-0000-0000-0000-000000000006')),
  'invalid_request', 'empty interval denied');
select is((select result_code from public.grant_care_assignment(
  '00000000-0000-0000-0000-000000000000', 'a9000000-0000-0000-0000-000000000001',
  public.phase2_test_member('11111111-1111-1111-1111-111111111111'::uuid),
  now(), null, 'a9100000-0000-0000-0000-000000000007')),
  'denied', 'cross-tenant operation denied without existence leak');
select is((select result_code from public.grant_care_assignment(
  public.phase2_test_org(), 'a1000000-0000-0000-0000-000000000001',
  public.phase2_test_member('33333333-3333-3333-3333-333333333333'::uuid),
  now(), null, 'a9100000-0000-0000-0000-000000000008')),
  'self_assignment_denied', 'self-assignment check independent of episode');

-- Assignment manager permission is required; a clinical actor cannot call the operation.
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
select is((select result_code from public.grant_care_assignment(
  public.phase2_test_org(), 'a9000000-0000-0000-0000-000000000001',
  public.phase2_test_member('22222222-2222-2222-2222-222222222222'::uuid),
  now(), null, 'a9100000-0000-0000-0000-000000000009')),
  'denied', 'actor without manage permission denied');
reset role;

-- Terminal episode guard and revocation behavior.
reset role;
update public.hospitalizations set status='cancelled' where id='a9000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
select is((select result_code from public.grant_care_assignment(
  public.phase2_test_org(), 'a9000000-0000-0000-0000-000000000001',
  public.phase2_test_member('11111111-1111-1111-1111-111111111111'::uuid),
  now(), null, 'a9100000-0000-0000-0000-000000000010')),
  'resource_denied', 'cancelled episode cannot be assigned');
reset role;
update public.hospitalizations set status='entered_in_error' where id='a9000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
select is((select result_code from public.grant_care_assignment(
  public.phase2_test_org(), 'a9000000-0000-0000-0000-000000000001',
  public.phase2_test_member('11111111-1111-1111-1111-111111111111'::uuid),
  now(), null, 'a9100000-0000-0000-0000-000000000012')),
  'resource_denied', 'invalidated episode cannot be assigned');
reset role;
update public.hospitalizations set status='admitted' where id='a9000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
select is((select result_code from public.revoke_care_assignment(
  public.phase2_test_org(),
  (select id from public.care_assignments where hospitalization_id='a9000000-0000-0000-0000-000000000001' and membership_id=public.phase2_test_member('11111111-1111-1111-1111-111111111111'::uuid)),
  'a9200000-0000-0000-0000-000000000001')),
  'revoked', 'assignment revoke succeeds');
select is((select result_code from public.revoke_care_assignment(
  public.phase2_test_org(),
  (select id from public.care_assignments where hospitalization_id='a9000000-0000-0000-0000-000000000001' and membership_id=public.phase2_test_member('11111111-1111-1111-1111-111111111111'::uuid)),
  'a9200000-0000-0000-0000-000000000002')),
  'already_revoked', 'repeated revocation is an audited no-op');
select ok((select replayed from public.revoke_care_assignment(
  public.phase2_test_org(),
  (select id from public.care_assignments where hospitalization_id='a9000000-0000-0000-0000-000000000001' and membership_id=public.phase2_test_member('11111111-1111-1111-1111-111111111111'::uuid)),
  'a9200000-0000-0000-0000-000000000002')), 'revoke replay is idempotent');
reset role;
update public.role_assignments assignment set revoked_at=now()
where assignment.organization_id=public.phase2_test_org()
  and assignment.membership_id=public.phase2_test_member('33333333-3333-3333-3333-333333333333'::uuid)
  and assignment.revoked_at is null
  and exists (
    select 1 from public.roles role
    where role.id=assignment.role_id and role.protected_kind='demo_administrator'
  );
set local role authenticated;
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
select is((select result_code || ':' || coalesce(assignment_id::text, 'null')
  from public.revoke_care_assignment(
    public.phase2_test_org(),
    (select id from public.care_assignments where hospitalization_id='a9000000-0000-0000-0000-000000000001' and membership_id=public.phase2_test_member('11111111-1111-1111-1111-111111111111'::uuid)),
    'a9200000-0000-0000-0000-000000000002')),
  'denied:null', 'revoked manage permission hides prior revoke replay');
reset role;
select is((select (select count(*)::text from public.audit_events where idempotency_key='a9200000-0000-0000-0000-000000000002')
  || ':' || (select (count(*) filter (where revoked_at is not null))::text from public.care_assignments where id=(select target_id from public.audit_events where idempotency_key='a9200000-0000-0000-0000-000000000002'))),
  '1:1', 'unauthorized revoke replay adds no audit and does not change effect');
update public.role_assignments assignment set revoked_at=null
where assignment.organization_id=public.phase2_test_org()
  and assignment.membership_id=public.phase2_test_member('33333333-3333-3333-3333-333333333333'::uuid)
  and exists (
    select 1 from public.roles role
    where role.id=assignment.role_id and role.protected_kind='demo_administrator'
  );
set local role authenticated;
select ok((select result_code='already_revoked' and replayed and assignment_id is not null
  from public.revoke_care_assignment(
    public.phase2_test_org(),
    (select id from public.care_assignments where hospitalization_id='a9000000-0000-0000-0000-000000000001' and membership_id=public.phase2_test_member('11111111-1111-1111-1111-111111111111'::uuid)),
    'a9200000-0000-0000-0000-000000000002')),
  'restored manage permission permits prior revoke replay');
select is((select count(*)::int from public.audit_events where idempotency_key='a9200000-0000-0000-0000-000000000002'),1,'authorized replay still preserves exactly one revoke audit');
select is((select count(*)::int from public.audit_events where action='care_assignment.revoke'),2,'one audit event per unique revoke key');
select is((select count(*)::int from public.audit_events where action='care_assignment.grant' and result='denied'),10,'resolvable denials are audited');
select ok((select bool_and(actor_auth_user_id is not null and actor_membership_id is not null) from public.audit_events where organization_id=public.phase2_test_org()),'audit actor derives from auth.uid');
select ok((select bool_and(not (metadata ? 'name') and not (metadata ? 'clinical_payload')) from public.audit_events),'audit metadata is sanitized');
select is((select count(*)::int from public.audit_events where metadata::text ~* '(email|password|jwt|token|rut|display_name|given_name|family_name|payload|summary)'),0,'audit metadata excludes identity credentials and clinical content');
select ok(has_table_privilege('authenticated','public.audit_events','select'),'authenticated has read grant gated by RLS');
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
select is((select count(*)::int from public.audit_events),0,'audit rows hidden absent audit.read in another actor context');
reset role;

select ok(not has_table_privilege('authenticated','public.care_assignments','insert'),'authenticated direct insert has no grant');
select ok(not has_table_privilege('authenticated','public.care_assignments','update'),'authenticated direct update has no grant');
select ok(not has_table_privilege('authenticated','public.care_assignments','delete'),'authenticated direct delete has no grant');
select ok(not has_table_privilege('authenticated','public.care_assignments','truncate'),'authenticated has no direct truncate privilege');
select ok(not (has_table_privilege('service_role','public.care_assignments','insert') or has_table_privilege('service_role','public.care_assignments','update') or has_table_privilege('service_role','public.care_assignments','delete') or has_table_privilege('service_role','public.care_assignments','truncate')),'service_role has no direct care-assignment write privilege');
select ok(not has_table_privilege('authenticated','public.audit_events','insert'),'authenticated cannot insert audit rows');
select ok(not has_function_privilege('anon','public.grant_care_assignment(uuid,uuid,uuid,timestamptz,timestamptz,uuid)','execute'),'anon cannot grant assignments');
set local role authenticated;
select throws_ok($$truncate table public.care_assignments$$,'42501',null,'authenticated cannot truncate care assignments');
select throws_ok($$insert into public.care_assignments (organization_id,hospitalization_id,membership_id,valid_from,created_by_membership_id) values ('00000000-0000-0000-0000-000000000000','a9000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000',now(),'00000000-0000-0000-0000-000000000000')$$,'42501',null,'authenticated direct care-assignment insert blocked');
select throws_ok($$insert into public.audit_events (organization_id,action,target_type,result,idempotency_key) values ('00000000-0000-0000-0000-000000000000','care_assignment.grant','care_assignment','denied',gen_random_uuid())$$,'42501',null,'authenticated direct audit insert blocked');
select throws_ok($$update public.care_assignments set revoked_at=now() where hospitalization_id='a9000000-0000-0000-0000-000000000001'$$,'42501',null,'authenticated direct care-assignment update blocked');
select throws_ok($$delete from public.care_assignments where hospitalization_id='a9000000-0000-0000-0000-000000000001'$$,'42501',null,'authenticated direct care-assignment delete blocked');
select throws_ok($$update public.audit_events set result='denied' where organization_id=public.phase2_test_org()$$,'42501',null,'authenticated audit update blocked');
select throws_ok($$delete from public.audit_events where organization_id=public.phase2_test_org()$$,'42501',null,'authenticated audit delete blocked');
reset role;
set local role service_role;
select throws_ok($$truncate table public.care_assignments$$,'42501',null,'service_role cannot truncate care assignments');
select throws_ok($$insert into public.care_assignments (organization_id,hospitalization_id,membership_id,valid_from,created_by_membership_id) values ('00000000-0000-0000-0000-000000000000','a9000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000',now(),'00000000-0000-0000-0000-000000000000')$$,'42501',null,'service_role direct care-assignment insert blocked');
select throws_ok($$insert into public.audit_events (organization_id,action,target_type,result,idempotency_key) values ('00000000-0000-0000-0000-000000000000','care_assignment.grant','care_assignment','denied',gen_random_uuid())$$,'42501',null,'service_role direct audit insert blocked');
select throws_ok($$update public.care_assignments set revoked_at=now() where hospitalization_id='a9000000-0000-0000-0000-000000000001'$$,'42501',null,'service_role direct care-assignment update blocked');
select throws_ok($$delete from public.care_assignments where hospitalization_id='a9000000-0000-0000-0000-000000000001'$$,'42501',null,'service_role direct care-assignment delete blocked');
select throws_ok($$update public.audit_events set result='denied' where organization_id=public.phase2_test_org()$$,'42501',null,'service_role audit update blocked');
select throws_ok($$delete from public.audit_events where organization_id=public.phase2_test_org()$$,'42501',null,'service_role audit delete blocked');
reset role;

select * from finish();
rollback;
