begin;
create extension if not exists pgtap;
select plan(62);
select public.bootstrap_synthetic_hospitalization_fixtures();

select ok((select relrowsecurity from pg_class where oid='public.units'::regclass), 'units has RLS');
select ok((select relrowsecurity from pg_class where oid='public.hospitalizations'::regclass), 'hospitalizations has RLS');
select ok((select relrowsecurity from pg_class where oid='public.hospitalization_locations'::regclass), 'locations has RLS');
select ok((select relrowsecurity from pg_class where oid='public.care_assignments'::regclass), 'care assignments has RLS');
select ok(not has_table_privilege('anon','public.hospitalizations','select'), 'anon has no grants');
select ok(not has_table_privilege('authenticated','public.care_assignments','insert'), 'authenticated cannot mutate assignments directly');
select is((select count(*)::int from public.hospitalizations where patient_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), 2, 'Elena has the two explicitly mapped episodes as owner');
select is((select count(*)::int from public.clinical_events where organization_id is null), 0, 'known synthetic seed events are mapped');
select is((select count(*)::int from public.care_assignments ca join public.organization_memberships m on m.id=ca.membership_id join public.profiles p on p.id=m.profile_id where p.auth_user_id='44444444-4444-4444-4444-444444444444'), 0, 'technician has no new care assignment');
select is((select count(*)::int from public.care_assignments ca join public.organization_memberships m on m.id=ca.membership_id join public.profiles p on p.id=m.profile_id where p.auth_user_id='55555555-5555-5555-5555-555555555555'), 0, 'suspended Camila has no care assignment');
select is((select count(*)::int from public.care_assignments ca join public.organization_memberships m on m.id=ca.membership_id join public.profiles p on p.id=m.profile_id where ca.hospitalization_id in ('a1000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000002','a1000000-0000-0000-0000-000000000003','a1000000-0000-0000-0000-000000000004','a1000000-0000-0000-0000-000000000005','a1000000-0000-0000-0000-000000000006','a1000000-0000-0000-0000-000000000007','a1000000-0000-0000-0000-000000000008','a1000000-0000-0000-0000-000000000009') and p.auth_user_id='11111111-1111-1111-1111-111111111111'), 5, 'Ana receives exactly the five explicitly approved assignments');
select is((select count(*)::int from public.care_assignments ca join public.organization_memberships m on m.id=ca.membership_id join public.profiles p on p.id=m.profile_id where ca.hospitalization_id in ('a1000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000002','a1000000-0000-0000-0000-000000000003','a1000000-0000-0000-0000-000000000004','a1000000-0000-0000-0000-000000000005','a1000000-0000-0000-0000-000000000006','a1000000-0000-0000-0000-000000000007','a1000000-0000-0000-0000-000000000008','a1000000-0000-0000-0000-000000000009') and p.auth_user_id='22222222-2222-2222-2222-222222222222'), 4, 'Matias receives exactly the four explicitly approved assignments');
select is((select count(*)::int from public.care_assignments ca join public.hospitalizations h on h.id=ca.hospitalization_id where h.patient_id='70000000-0000-0000-0000-000000000008'), 0, 'Óscar has no assignment');
select is((select count(*)::int from public.care_assignments ca join public.hospitalizations h on h.id=ca.hospitalization_id join public.organization_memberships m on m.id=ca.membership_id join public.profiles p on p.id=m.profile_id where h.patient_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and p.auth_user_id='22222222-2222-2222-2222-222222222222'), 0, 'Matias assignment does not follow recorded event authorship');

select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select ok(private.has_current_care_assignment('a1000000-0000-0000-0000-000000000001'), 'seed bridge is idempotent and creates current assignment');
select ok(private.has_current_care_assignment('a1000000-0000-0000-0000-000000000002'), 'assignment retains historical episode access');
select ok(not has_function_privilege('anon','private.has_current_care_assignment(uuid)','execute'), 'anon cannot invoke internal authorization helper');

-- A second episode for the same patient is not authorized just because another is.
insert into public.hospitalizations (id,organization_id,patient_id,status,admitted_at)
select 'a2000000-0000-0000-0000-000000000001', organization_id, id, 'admitted', now()
from public.patients where id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
insert into public.hospitalizations (id,organization_id,patient_id,status,admitted_at)
select 'a3000000-0000-0000-0000-000000000001', organization_id, id, 'admitted', now()
from public.patients where id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
insert into public.care_assignments (organization_id,hospitalization_id,membership_id,valid_from,created_by_membership_id)
select h.organization_id,h.id,m.id,now()-interval '1 hour',m_admin.id
from public.hospitalizations h
join public.organizations o on o.id=h.organization_id and o.slug='demo-hospital'
join public.organization_memberships m on m.organization_id=o.id
join public.profiles p on p.id=m.profile_id and p.auth_user_id='22222222-2222-2222-2222-222222222222'
join public.organization_memberships m_admin on m_admin.organization_id=o.id
join public.profiles p_admin on p_admin.id=m_admin.profile_id and p_admin.auth_user_id='33333333-3333-3333-3333-333333333333'
where h.id='a2000000-0000-0000-0000-000000000001';

-- Adjacent periods/grants are valid; overlapping live periods/grants fail through
-- PostgreSQL exclusion constraints (23P01), including concurrent competing inserts.
insert into public.hospitalization_locations (organization_id,hospitalization_id,unit_id,bed_label,started_at,ended_at)
select h.organization_id,h.id,unit.unit_id,period.bed,period.started_at,period.ended_at
from public.hospitalizations h
cross join lateral (select unit_id from public.hospitalization_locations where hospitalization_id='a1000000-0000-0000-0000-000000000001' limit 1) unit
cross join (values ('Bed A'::text,now()-interval '2 days',now()-interval '1 day'),('Bed B'::text,now()-interval '1 day',now())) period(bed,started_at,ended_at)
where h.id='a3000000-0000-0000-0000-000000000001';
select is((select count(*)::int from public.hospitalization_locations where hospitalization_id='a3000000-0000-0000-0000-000000000001'),2,'adjacent location intervals are allowed');
select throws_ok($$insert into public.hospitalization_locations (organization_id,hospitalization_id,unit_id,started_at,ended_at) select h.organization_id,h.id,l.unit_id,now()-interval '12 hours',now()+interval '1 hour' from public.hospitalizations h cross join lateral (select unit_id from public.hospitalization_locations where hospitalization_id='a1000000-0000-0000-0000-000000000001' limit 1) l where h.id='a3000000-0000-0000-0000-000000000001'$$,'23P01',null,'overlapping location interval is rejected by exclusion constraint');
insert into public.care_assignments (organization_id,hospitalization_id,membership_id,valid_from,valid_until,created_by_membership_id)
select h.organization_id,h.id,ana.id,period.valid_from,period.valid_until,admin.id
from public.hospitalizations h
cross join lateral (select m.id from public.organization_memberships m join public.profiles p on p.id=m.profile_id where p.auth_user_id='11111111-1111-1111-1111-111111111111' and m.organization_id=h.organization_id) ana
cross join lateral (select m.id from public.organization_memberships m join public.profiles p on p.id=m.profile_id where p.auth_user_id='33333333-3333-3333-3333-333333333333' and m.organization_id=h.organization_id) admin
cross join (values (now()-interval '10 days',now()-interval '5 days'),(now()-interval '5 days',now()-interval '1 day')) period(valid_from,valid_until)
where h.id='a3000000-0000-0000-0000-000000000001';
select is((select count(*)::int from public.care_assignments ca join public.organization_memberships m on m.id=ca.membership_id join public.profiles p on p.id=m.profile_id where ca.hospitalization_id='a3000000-0000-0000-0000-000000000001' and p.auth_user_id='11111111-1111-1111-1111-111111111111' and ca.revoked_at is null),2,'adjacent care-assignment intervals are allowed');
select throws_ok($$insert into public.care_assignments (organization_id,hospitalization_id,membership_id,valid_from,valid_until,created_by_membership_id) select h.organization_id,h.id,ana.id,now()-interval '6 days',now()-interval '4 days',admin.id from public.hospitalizations h cross join lateral (select m.id from public.organization_memberships m join public.profiles p on p.id=m.profile_id where p.auth_user_id='11111111-1111-1111-1111-111111111111' and m.organization_id=h.organization_id) ana cross join lateral (select m.id from public.organization_memberships m join public.profiles p on p.id=m.profile_id where p.auth_user_id='33333333-3333-3333-3333-333333333333' and m.organization_id=h.organization_id) admin where h.id='a3000000-0000-0000-0000-000000000001'$$,'23P01',null,'overlapping equivalent live assignment rejected by exclusion constraint');
insert into public.care_assignments (organization_id,hospitalization_id,membership_id,valid_from,valid_until,revoked_at,created_by_membership_id)
select h.organization_id,h.id,ana.id,now()-interval '6 days',now()-interval '4 days',now(),admin.id
from public.hospitalizations h
cross join lateral (select m.id from public.organization_memberships m join public.profiles p on p.id=m.profile_id where p.auth_user_id='11111111-1111-1111-1111-111111111111' and m.organization_id=h.organization_id) ana
cross join lateral (select m.id from public.organization_memberships m join public.profiles p on p.id=m.profile_id where p.auth_user_id='33333333-3333-3333-3333-333333333333' and m.organization_id=h.organization_id) admin
where h.id='a3000000-0000-0000-0000-000000000001';
select is((select count(*)::int from public.care_assignments where hospitalization_id='a3000000-0000-0000-0000-000000000001' and revoked_at is not null),1,'revoked overlapping history does not block a live grant');
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select ok(private.has_current_care_assignment('a1000000-0000-0000-0000-000000000001'), 'Ana assignment is current');
select ok(not private.has_current_care_assignment('a2000000-0000-0000-0000-000000000001'), 'same patient does not transfer assignment to another episode');

-- A location transfer on the same episode leaves the assignment unchanged.
update public.hospitalization_locations set ended_at=now() where hospitalization_id='a1000000-0000-0000-0000-000000000001' and ended_at is null;
insert into public.hospitalization_locations (organization_id,hospitalization_id,unit_id,bed_label,started_at)
select h.organization_id,h.id,l.unit_id,'Cama trasladada',now()
from public.hospitalizations h join public.hospitalization_locations l on l.hospitalization_id=h.id
where h.id='a1000000-0000-0000-0000-000000000001' limit 1;
select ok(private.has_current_care_assignment('a1000000-0000-0000-0000-000000000001'), 'unit transfer does not alter episode assignment');

insert into public.care_assignments (organization_id,hospitalization_id,membership_id,valid_from,valid_until,created_by_membership_id)
select h.organization_id,h.id,m.id,now()+interval '1 day',now()+interval '2 days',m.id
from public.hospitalizations h join public.organization_memberships m on m.organization_id=h.organization_id
join public.profiles p on p.id=m.profile_id and p.auth_user_id='11111111-1111-1111-1111-111111111111'
where h.id='a3000000-0000-0000-0000-000000000001';
select ok(not private.has_current_care_assignment('a3000000-0000-0000-0000-000000000001'), 'future assignment is not current');
update public.care_assignments set valid_from=now()-interval '20 days',valid_until=now()-interval '19 days'
where hospitalization_id='a3000000-0000-0000-0000-000000000001' and membership_id=(select m.id from public.organization_memberships m join public.profiles p on p.id=m.profile_id where p.auth_user_id='11111111-1111-1111-1111-111111111111' and m.organization_id=(select id from public.organizations where slug='demo-hospital')) and valid_from=now()+interval '1 day';
select ok(not private.has_current_care_assignment('a3000000-0000-0000-0000-000000000001'), 'expired assignment is not current');
update public.care_assignments set valid_from=now()-interval '1 day',valid_until=null,revoked_at=now()
where hospitalization_id='a3000000-0000-0000-0000-000000000001' and membership_id=(select m.id from public.organization_memberships m join public.profiles p on p.id=m.profile_id where p.auth_user_id='11111111-1111-1111-1111-111111111111' and m.organization_id=(select id from public.organizations where slug='demo-hospital')) and valid_from=now()-interval '20 days';
select ok(not private.has_current_care_assignment('a3000000-0000-0000-0000-000000000001'), 'revoked assignment is not current');

update public.care_assignments set revoked_at=null,valid_from=now()-interval '1 day',valid_until=null
where hospitalization_id='a3000000-0000-0000-0000-000000000001' and membership_id=(select m.id from public.organization_memberships m join public.profiles p on p.id=m.profile_id where p.auth_user_id='11111111-1111-1111-1111-111111111111' and m.organization_id=(select id from public.organizations where slug='demo-hospital')) and valid_from=now()-interval '1 day' and revoked_at is not null;
select ok(private.has_current_care_assignment('a3000000-0000-0000-0000-000000000001'), 'restored assignment is current before episode cancellation');
update public.hospitalizations set status='cancelled',discharged_at=null where id='a3000000-0000-0000-0000-000000000001';
select ok(not private.has_current_care_assignment('a3000000-0000-0000-0000-000000000001'), 'cancelled episode is denied');
update public.hospitalizations set status='admitted',discharged_at=null where id='a3000000-0000-0000-0000-000000000001';
select ok(private.has_current_care_assignment('a3000000-0000-0000-0000-000000000001'), 'active episode remains authorized with current assignment');
update public.hospitalizations set status='entered_in_error',discharged_at=null where id='a3000000-0000-0000-0000-000000000001';
select ok(not private.has_current_care_assignment('a3000000-0000-0000-0000-000000000001'), 'invalidated episode is denied');

update public.profiles set status='suspended' where auth_user_id='11111111-1111-1111-1111-111111111111';
select ok(not private.has_current_care_assignment('a1000000-0000-0000-0000-000000000001'), 'suspended profile invalidates assignment');
update public.profiles set status='active' where auth_user_id='11111111-1111-1111-1111-111111111111';
update public.organization_memberships set status='suspended' where profile_id=(select id from public.profiles where auth_user_id='11111111-1111-1111-1111-111111111111');
select ok(not private.has_current_care_assignment('a1000000-0000-0000-0000-000000000001'), 'suspended membership invalidates assignment');
update public.organization_memberships set status='active' where profile_id=(select id from public.profiles where auth_user_id='11111111-1111-1111-1111-111111111111');

select throws_ok($$insert into public.hospitalization_locations (organization_id,hospitalization_id,unit_id,started_at,ended_at) values ('00000000-0000-0000-0000-000000000000','a1000000-0000-0000-0000-000000000001',null,now(),now()-interval '1 hour')$$, '23514', null, 'location interval must be positive');
select throws_ok($$insert into public.hospitalization_locations (organization_id,hospitalization_id,unit_id,started_at) values ((select id from public.organizations where slug='demo-hospital'),'a2000000-0000-0000-0000-000000000001','82000000-0000-0000-0000-000000000001',now())$$, '23503', null, 'location unit FK rejects cross-tenant unit');
select throws_ok($$insert into public.care_assignments (organization_id,hospitalization_id,membership_id,valid_from,valid_until,created_by_membership_id) select h.organization_id,h.id,m.id,now(),now(),m.id from public.hospitalizations h join public.organization_memberships m on m.organization_id=h.organization_id where h.id='a1000000-0000-0000-0000-000000000001' limit 1$$, '23514', null, 'assignment interval must be positive');

-- Tenant B has its own synthetic membership/assignment; Ana must not see either row.
insert into public.organizations (id,slug,display_name) values ('b2000000-0000-0000-0000-000000000001','phase2-test-tenant','Phase 2 test tenant');
insert into public.patients (id,organization_id,given_name,family_name)
values ('b3000000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000001','Synthetic','Tenant B');
insert into public.units (id,organization_id,code,display_name)
values ('b2500000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000001','TEST-B','Tenant B Unit');
insert into public.organization_memberships (id,organization_id,profile_id,status)
select 'b4000000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000001',id,'active'
from public.profiles where auth_user_id='44444444-4444-4444-4444-444444444444';
insert into public.hospitalizations (id,organization_id,patient_id,status,admitted_at)
values ('b5000000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000001','admitted',now());
insert into public.care_assignments (organization_id,hospitalization_id,membership_id,valid_from,created_by_membership_id)
values ('b2000000-0000-0000-0000-000000000001','b5000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000001',now()-interval '1 hour','b4000000-0000-0000-0000-000000000001');

select throws_ok($$update public.clinical_events set organization_id=null where id='cccccccc-cccc-cccc-cccc-cccccccccccc'$$,'23514',null,'event cannot have a partial episode link');
select throws_ok($$update public.clinical_events set hospitalization_id='a1000000-0000-0000-0000-000000000003' where id='cccccccc-cccc-cccc-cccc-cccccccccccc'$$,'23503',null,'event patient must match episode patient');
select throws_ok($$update public.clinical_events set organization_id='b2000000-0000-0000-0000-000000000001' where id='cccccccc-cccc-cccc-cccc-cccccccccccc'$$,'23503',null,'event tenant must match episode tenant');
insert into public.clinical_events (id,patient_id,recorded_by,kind,occurred_at,payload)
values ('90000000-0000-0000-0000-000000000010','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',null,'encounter',now(),' {"summary":"Unpublished synthetic event"}'::jsonb);
select ok((select organization_id is null and hospitalization_id is null from public.clinical_events where id='90000000-0000-0000-0000-000000000010'),'unpublished event may keep both links null');

-- A role with assignment.manage+census is not a clinical organization-read grant.
insert into public.roles (id,organization_id,name,description)
select '87000000-0000-0000-0000-000000000001',id,'Assignment manager test','Synthetic role without organization clinical read'
from public.organizations where slug='demo-hospital';
insert into public.role_permissions (organization_id,role_id,permission_code)
select r.organization_id,r.id,p.code from public.roles r cross join (values ('clinical.assignment.manage'),('clinical.census.read')) p(code)
where r.id='87000000-0000-0000-0000-000000000001';
insert into public.role_assignments (id,organization_id,membership_id,role_id,scope_type,valid_from,created_by_membership_id)
select '88000000-0000-0000-0000-000000000001',m.organization_id,m.id,r.id,'organization',now()-interval '1 hour',m.id
from public.organization_memberships m join public.profiles p on p.id=m.profile_id
join public.roles r on r.organization_id=m.organization_id and r.id='87000000-0000-0000-0000-000000000001'
where p.auth_user_id='11111111-1111-1111-1111-111111111111' and m.organization_id=r.organization_id;

-- RLS is checked as the actual API role; clinical table policies are tightened in phase 3.
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select ok(public.has_active_iam_permission((select id from public.organizations where slug='demo-hospital'),'clinical.assignment.manage'),'test actor has assignment.manage');
select ok(not public.has_active_iam_permission((select id from public.organizations where slug='demo-hospital'),'clinical.organization.read'),'test actor lacks reserved organization-read');
select is((select count(*)::int from public.hospitalizations where id='a1000000-0000-0000-0000-000000000003'),0,'assignment.manage+census alone does not grant global census');
select is((select count(*)::int from public.hospitalization_locations where hospitalization_id='a1000000-0000-0000-0000-000000000003'),0,'assignment.manage+census alone does not grant global location reads');
select is((select count(*)::int from public.units where organization_id=(select id from public.organizations where slug='demo-hospital')),0,'clinical staff cannot enumerate units without org.unit.read');
select is((select count(*)::int from public.hospitalization_locations where hospitalization_id='a1000000-0000-0000-0000-000000000001' and unit_id is not null and bed_label is not null),2,'assigned clinical staff retain authorized location unit/bed details');
select is((select count(*)::int from public.hospitalizations where id='b5000000-0000-0000-0000-000000000001'),0,'membership in another tenant does not grant clinical census permission');
select is((select count(*)::int from public.care_assignments where hospitalization_id='b5000000-0000-0000-0000-000000000001'),0,'cross-tenant episode and assignment stay hidden');
select is((select count(*)::int from public.hospitalizations where id='a1000000-0000-0000-0000-000000000001'),1,'assigned hospitalization visible');
select is((select count(*)::int from public.hospitalizations where id='a1000000-0000-0000-0000-000000000003'),0,'unassigned hospitalization hidden');
select is((select count(*)::int from public.hospitalization_locations where hospitalization_id='a1000000-0000-0000-0000-000000000003'),0,'unassigned location hidden');
select set_config('request.jwt.claim.sub','44444444-4444-4444-4444-444444444444',true);
select is((select count(*)::int from public.units where organization_id=(select id from public.organizations where slug='demo-hospital')),0,'technician without org.unit.read cannot enumerate units');
select is((select count(*)::int from public.units where organization_id='b2000000-0000-0000-0000-000000000001'),0,'active membership in another tenant cannot enumerate its units');
select is((select count(*)::int from public.care_assignments ca where public.is_current_active_membership(ca.membership_id) and ca.organization_id=(select id from public.organizations where slug='demo-hospital')),0,'technician has no demo care assignment visible');
select is((select count(*)::int from public.hospitalizations where id='a1000000-0000-0000-0000-000000000003'),0,'recorded_by does not authorize technician');
select set_config('request.jwt.claim.sub','33333333-3333-3333-3333-333333333333',true);
select ok(public.has_active_iam_permission((select id from public.organizations where slug='demo-hospital'),'org.unit.read'),'protected administrator has org.unit.read');
select is((select count(*)::int from public.units where organization_id=(select id from public.organizations where slug='demo-hospital') and code in ('medicine','surgery','adult-icu','pediatrics','emergency','intermediate-care')),6,'administrator can read legacy units in own tenant');
select is((select count(*)::int from public.units where organization_id='b2000000-0000-0000-0000-000000000001'),0,'administrator cannot enumerate units across tenants');
select is((select count(*)::int from public.hospitalizations where id='a1000000-0000-0000-0000-000000000003'),1,'protected administrator with organization.read sees tenant census');
select is((select count(*)::int from public.hospitalization_locations where hospitalization_id='a1000000-0000-0000-0000-000000000003'),1,'protected administrator sees tenant locations');
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select is((select count(*)::int from public.hospitalizations where id='a1000000-0000-0000-0000-000000000002'),1,'historical episode remains visible while assignment remains current');
reset role;

select * from finish();
rollback;
