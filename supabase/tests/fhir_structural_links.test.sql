begin;
create extension if not exists pgtap;
select plan(20);
insert into public.fhir_sources (id,organization_id,logical_key) values
 ('f2000000-0000-0000-0000-000000000001',(select id from public.organizations where slug='demo-hospital'),'test-fhir-structural');
insert into public.fhir_patient_links (organization_id,source_id,fhir_id,patient_id) values
 ((select id from public.organizations where slug='demo-hospital'),'f2000000-0000-0000-0000-000000000001','pat-123.a','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
insert into public.fhir_encounter_links (organization_id,source_id,fhir_id,hospitalization_id,patient_id) values
 ((select id from public.organizations where slug='demo-hospital'),'f2000000-0000-0000-0000-000000000001','enc-A.9','a1000000-0000-0000-0000-000000000001','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
insert into public.fhir_location_links (organization_id,source_id,fhir_id,unit_id) values
 ((select id from public.organizations where slug='demo-hospital'),'f2000000-0000-0000-0000-000000000001','loc-west-1',(select id from public.units limit 1));
select has_table('public','fhir_sources','source registry exists');
select has_table('public','fhir_patient_links','patient links exist');
select has_table('public','fhir_encounter_links','encounter links exist');
select has_table('public','fhir_location_links','location links exist');
select ok(not has_table_privilege('authenticated','public.fhir_sources','select') and not has_table_privilege('service_role','public.fhir_sources','select'),'sources not runtime-readable');
select ok(has_function_privilege('authenticated','public.fhir_authorized_encounter_context(uuid,uuid,text)','execute') and not has_function_privilege('anon','public.fhir_authorized_encounter_context(uuid,uuid,text)','execute') and not has_function_privilege('service_role','public.fhir_authorized_encounter_context(uuid,uuid,text)','execute'),'context RPC is JWT-only');
select is((select count(*) from public.fhir_authorized_encounter_context((select id from public.organizations where slug='demo-hospital'),'c2000000-0000-0000-0000-000000000003','record')),0::bigint,'unauthorized request returns no context');
select ok((select pg_get_constraintdef(oid) like '%fhir_id%' from pg_constraint where conname='fhir_patient_links_pkey'),'external FHIR id is text mapping key, not UUID');
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select is((select count(*) from public.fhir_authorized_encounter_context((select id from public.organizations where slug='demo-hospital'),'a1000000-0000-0000-0000-000000000001','record')),1::bigint,'assigned practitioner gets episode record context');
select is((select count(*) from public.fhir_authorized_encounter_context((select id from public.organizations where slug='demo-hospital'),'a1000000-0000-0000-0000-000000000003','record')),0::bigint,'episode assigned to another clinician is denied');
select is((select count(*) from public.fhir_authorized_encounter_context('c2000000-0000-0000-0000-000000000099','a1000000-0000-0000-0000-000000000001','record')),0::bigint,'foreign tenant receives no context');
select is((select count(*) from public.fhir_authorized_encounter_context((select id from public.organizations where slug='demo-hospital'),'a1000000-0000-0000-0000-000000000001','timeline')),1::bigint,'timeline purpose permits when timeline permission exists');
reset role;
delete from public.role_permissions where organization_id=(select id from public.organizations where slug='demo-hospital') and permission_code='clinical.timeline.read';
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select is((select count(*) from public.fhir_authorized_encounter_context((select id from public.organizations where slug='demo-hospital'),'a1000000-0000-0000-0000-000000000001','record')),1::bigint,'record purpose does not require timeline permission');
select is((select count(*) from public.fhir_authorized_encounter_context((select id from public.organizations where slug='demo-hospital'),'a1000000-0000-0000-0000-000000000001','timeline')),0::bigint,'timeline purpose denied without timeline permission');
reset role;
update public.care_assignments set revoked_at=now(), revoked_by_membership_id=created_by_membership_id
where hospitalization_id='a1000000-0000-0000-0000-000000000001'
  and membership_id=(select m.id from public.organization_memberships m join public.profiles p on p.id=m.profile_id where p.auth_user_id='11111111-1111-1111-1111-111111111111' and m.organization_id=(select id from public.organizations where slug='demo-hospital'));
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select is((select count(*) from public.fhir_authorized_encounter_context((select id from public.organizations where slug='demo-hospital'),'a1000000-0000-0000-0000-000000000001','record')),0::bigint,'revoked care assignment denied');
reset role;
update public.organization_memberships set status='suspended' where organization_id=(select id from public.organizations where slug='demo-hospital') and profile_id=(select id from public.profiles where auth_user_id='11111111-1111-1111-1111-111111111111');
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select is((select count(*) from public.fhir_authorized_encounter_context((select id from public.organizations where slug='demo-hospital'),'a1000000-0000-0000-0000-000000000001','record')),0::bigint,'suspended membership denied');
reset role;
select throws_ok($$select * from public.fhir_authorized_encounter_context((select id from public.organizations where slug='demo-hospital'),'a1000000-0000-0000-0000-000000000001',null)$$,'22023',null,'null purpose rejected');
reset role;
select throws_ok($$insert into public.fhir_encounter_links values ((select id from public.organizations where slug='demo-hospital'),'f2000000-0000-0000-0000-000000000001','enc-wrong','a1000000-0000-0000-0000-000000000002','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')$$,'23503',null,'episode/patient mismatch fails composite FK');
select throws_ok($$insert into public.fhir_patient_links values ((select id from public.organizations where slug='demo-hospital'),'f2000000-0000-0000-0000-000000000001','bad/id','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')$$,'23514',null,'FHIR id format enforced');
select ok(not exists(select 1 from information_schema.columns where table_schema='public' and table_name='fhir_location_links' and column_name='location_id'),'location mapping has no fabricated internal location id');
select * from finish();
rollback;
