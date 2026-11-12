begin;
select plan(60);
select ok((select relrowsecurity from pg_class where oid='public.period_summaries'::regclass),'RLS enabled');
select ok(not has_table_privilege('authenticated','public.period_summaries','INSERT'),'no direct insert');
select ok(not has_table_privilege('authenticated','public.period_summaries','UPDATE'),'no update');
select ok(not has_table_privilege('authenticated','public.period_summaries','DELETE'),'no delete');
select ok(not has_table_privilege('authenticated','public.period_summaries','TRUNCATE'),'no truncate');
select ok(not has_table_privilege('service_role','public.period_summaries','SELECT'),'no service role select');
select ok(not has_function_privilege('anon','public.save_period_summary(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,text,timestamp with time zone,text,text,text,text[],integer,jsonb)','EXECUTE'),'anon cannot save');
select ok(not has_function_privilege('service_role','public.period_summary_context(uuid,uuid)','EXECUTE'),'service role cannot use context RPC');

create function pg_temp.ps_source(p_id text,p_kind text default 'context_note') returns jsonb language sql as $$ select jsonb_build_array(jsonb_build_object('id',p_id,'kind',p_kind,'occurred_at',to_char(now()-interval '1 hour','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'precision','instant')) $$;

create function pg_temp.ps_date(p_date date,p_id text default 'note-date') returns jsonb language sql as $$ select jsonb_build_array(jsonb_build_object('id',p_id,'kind','context_note','occurred_at',p_date::text,'precision','date')) $$;

create temporary table ps_fixture as
select o.id org,'d2000000-0000-0000-0000-000000000001'::uuid episode,
 'd2000000-0000-0000-0000-000000000002'::uuid patient,o.timezone
from public.organizations o where o.slug='demo-hospital';
insert into public.organizations(id,slug,display_name) values ('d2000000-0000-0000-0000-000000000010','period-summary-other','Other synthetic tenant');
insert into public.patients(id,organization_id,given_name,family_name) values ('d2000000-0000-0000-0000-000000000011','d2000000-0000-0000-0000-000000000010','Other','Tenant');
insert into public.hospitalizations(id,organization_id,patient_id,status,admitted_at) values ('d2000000-0000-0000-0000-000000000012','d2000000-0000-0000-0000-000000000010','d2000000-0000-0000-0000-000000000011','admitted',now()-interval '1 day');
insert into public.patients(id,organization_id,given_name,family_name)
select patient,org,'Synthetic','Summary' from ps_fixture;
insert into public.hospitalizations(id,organization_id,patient_id,status,admitted_at) select 'd2000000-0000-0000-0000-000000000003',org,patient,'admitted',now()-interval '1 day' from ps_fixture;
insert into public.hospitalizations(id,organization_id,patient_id,status,admitted_at)
select episode,org,patient,'admitted',now()-interval '1 day' from ps_fixture;
insert into public.care_assignments(organization_id,hospitalization_id,membership_id,valid_from,created_by_membership_id)
select f.org,f.episode,m.id,now()-interval '1 day',admin.id
from ps_fixture f
join public.profiles p on p.auth_user_id in ('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222')
join public.organization_memberships m on m.profile_id=p.id and m.organization_id=f.org
join public.profiles ap on ap.auth_user_id='33333333-3333-3333-3333-333333333333'
join public.organization_memberships admin on admin.profile_id=ap.id and admin.organization_id=f.org;
insert into public.role_permissions(organization_id,role_id,permission_code)
select r.organization_id,r.id,'clinical.summary.use' from public.roles r
join public.organizations o on o.id=r.organization_id where o.slug='demo-hospital'
and (r.protected_kind='demo_administrator' or r.name='Personal clínico') on conflict do nothing;
grant select on ps_fixture to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select is((select patient_id from public.period_summary_context((select org from ps_fixture),(select episode from ps_fixture))),(select patient from ps_fixture),'authorized patient derives from episode');
select is((select timezone from public.period_summary_context((select org from ps_fixture),(select episode from ps_fixture))),(select timezone from ps_fixture),'institution timezone returned');
select lives_ok($$select public.save_period_summary('d1000000-0000-0000-0000-000000000001',org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'Snapshot clínico sintético','model-v1','prompt-v1',array['context_note'],0,pg_temp.ps_source('note-1')) from ps_fixture$$,'assigned clinician saves summary');
select is((select count(*) from public.period_summaries),1::bigint,'author reads own summary');
select lives_ok($$select public.save_period_summary('d1000000-0000-0000-0000-000000000001',org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'Snapshot clínico sintético','model-v1','prompt-v1',array['context_note'],0,pg_temp.ps_source('note-1')) from ps_fixture$$,'identical retry returns prior summary');
select throws_ok($$select public.save_period_summary('d1000000-0000-0000-0000-000000000001',org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'different','model-v1','prompt-v1',array['context_note'],0,pg_temp.ps_source('note-1')) from ps_fixture$$,null,null,'same UUID changed payload rejects');
select throws_ok($$select public.save_period_summary(null,org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'x','m','p',array['context_note'],0,pg_temp.ps_source('n')) from ps_fixture$$,null,null,'null id rejects');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),org,episode,patient,now()-interval '2 hours',now(),timezone,now(),' ','m','p',array['context_note'],0,pg_temp.ps_source('n')) from ps_fixture$$,null,null,'blank content rejects');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),org,episode,patient,now()-interval '2 hours',now(),timezone,now(),repeat('x',20001),'m','p',array['context_note'],0,pg_temp.ps_source('n')) from ps_fixture$$,null,null,'oversized content rejects');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'x',' ','p',array['context_note'],0,pg_temp.ps_source('n')) from ps_fixture$$,null,null,'blank model version rejects');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'x','m','p',array[]::text[],0,pg_temp.ps_source('n')) from ps_fixture$$,null,null,'empty kinds reject');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'x','m','p',array['context_note',null],0,pg_temp.ps_source('n')) from ps_fixture$$,null,null,'null kind rejects');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'x','m','p',array['context_note','context_note'],0,pg_temp.ps_source('n')) from ps_fixture$$,null,null,'duplicate kinds reject');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'x','m','p',array['context_note'],0,'[]') from ps_fixture$$,null,null,'empty source list rejects');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'x','m','p',array['context_note'],0,'[{"id":"n","kind":"context_note","occurred_at":"2026-11-08T10:00:00Z","precision":null}]') from ps_fixture$$,null,null,'JSON null precision rejects');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'x','m','p',array['context_note'],0,'[{"id":"n","kind":null,"occurred_at":"2026-11-08T10:00:00Z","precision":"instant"}]') from ps_fixture$$,null,null,'JSON null kind rejects');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'x','m','p',array['context_note'],0,'[{"id":"n","kind":"context_note","occurred_at":null,"precision":"instant"}]') from ps_fixture$$,null,null,'JSON null time rejects');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'x','m','p',array['context_note'],0,'[{"id":"n","kind":"context_note","occurred_at":"2026-11-08T10:00:00","precision":"instant"}]') from ps_fixture$$,null,null,'instant without timezone offset rejects');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'x','m','p',array['context_note'],0,jsonb_build_array(jsonb_build_object('id','n','kind','context_note','occurred_at',to_char(now()+interval '1 second','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'precision','instant'))) from ps_fixture$$,null,null,'instant outside half-open window rejects');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),org,episode,patient,'infinity',now(),timezone,now(),'x','m','p',array['context_note'],0,pg_temp.ps_source('n')) from ps_fixture$$,null,null,'infinite timestamp rejects');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),org,episode,patient,now()-interval '2 hours',now()+interval '1 day',timezone,now(),'x','m','p',array['context_note'],0,pg_temp.ps_source('n')) from ps_fixture$$,null,null,'future end rejects');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'x','m','p',array['context_note'],0,'[{"id":"n","kind":"context_note","occurred_at":"not-date","precision":"date"}]') from ps_fixture$$,null,null,'malformed date rejects');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'x','m','p',array['context_note'],0,pg_temp.ps_date((now()+interval '1 day')::date)) from ps_fixture$$,null,null,'date outside local range rejects');
select lives_ok($$select public.save_period_summary('d1000000-0000-0000-0000-000000000004',org,episode,patient,((now() at time zone timezone)::date::timestamp at time zone timezone),now(),timezone,now(),'Date precision snapshot','model-v1','prompt-v1',array['context_note','Condition','Observation','MedicationRequest'],0,pg_temp.ps_date((now() at time zone timezone)::date)) from ps_fixture$$,'institution-local date precision and all selected kinds accepted');
select lives_ok($$select public.save_period_summary('d1000000-0000-0000-0000-000000000005',org,episode,patient,((now() at time zone timezone)::date::timestamp at time zone timezone),now(),timezone,now(),'All timeline sources','model-v1','prompt-v1',array['context_note','Condition','Observation','MedicationRequest','Procedure','DiagnosticReport'],0,pg_temp.ps_source('note-all') || pg_temp.ps_source('condition','Condition') || pg_temp.ps_source('observation','Observation') || pg_temp.ps_source('medication','MedicationRequest') || pg_temp.ps_source('procedure','Procedure') || pg_temp.ps_source('report','DiagnosticReport')) from ps_fixture$$,'all six source kinds including all timeline FHIR kinds accepted');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'x','m','p',array['context_note'],0,pg_temp.ps_source('n','AllergyIntolerance')) from ps_fixture$$,null,null,'unsupported source kind rejects');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'x','m','p',array['context_note'],0,pg_temp.ps_source('n','Observation')) from ps_fixture$$,null,null,'source kind not selected rejects');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','22222222-2222-2222-2222-222222222222',true);
select is((select count(*) from public.period_summaries),0::bigint,'second authorized clinician cannot read another author snapshot');
select lives_ok($$select public.save_period_summary('d1000000-0000-0000-0000-000000000002',org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'Colleague snapshot','model-v1','prompt-v1',array['context_note'],0,pg_temp.ps_source('note-2')) from ps_fixture$$,'second assigned author creates own snapshot');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-3333-3333-333333333333',true);
select is((select count(*) from public.period_summaries),0::bigint,'admin cannot read another author snapshot');
select throws_ok($$select public.save_period_summary('d1000000-0000-0000-0000-000000000001',org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'Snapshot clínico sintético','model-v1','prompt-v1',array['context_note'],0,pg_temp.ps_source('note-1')) from ps_fixture$$,null,null,'admin cannot replay another author id');
select lives_ok($$select public.save_period_summary('d1000000-0000-0000-0000-000000000003',org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'Admin own snapshot','model-v1','prompt-v1',array['context_note'],0,pg_temp.ps_source('note-3')) from ps_fixture$$,'admin with own episode access creates own snapshot');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','55555555-5555-5555-5555-555555555555',true);
select is((select count(*) from public.period_summary_context((select org from ps_fixture),(select episode from ps_fixture))),0::bigint,'suspended member denied context');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'x','m','p',array['context_note'],0,pg_temp.ps_source('n')) from ps_fixture$$,'42501',null,'suspended member denied save');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select is((select count(*) from public.period_summary_context('d2000000-0000-0000-0000-000000000010','d2000000-0000-0000-0000-000000000012')),0::bigint,'cross-tenant context is hidden');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),'d2000000-0000-0000-0000-000000000010','d2000000-0000-0000-0000-000000000012','d2000000-0000-0000-0000-000000000011',now()-interval '2 hours',now(),'America/Santiago',now(),'x','m','p',array['context_note'],0,pg_temp.ps_source('n'))$$,'42501',null,'cross-tenant save denied');
select is((select count(*) from public.period_summary_context((select org from ps_fixture),'d2000000-0000-0000-0000-000000000003')),0::bigint,'same-tenant unassigned episode context hidden');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),org,'d2000000-0000-0000-0000-000000000003',patient,now()-interval '2 hours',now(),timezone,now(),'x','m','p',array['context_note'],0,pg_temp.ps_source('n')) from ps_fixture$$,'42501',null,'same-tenant unassigned episode save denied');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),org,episode,'d2000000-0000-0000-0000-000000000011',now()-interval '2 hours',now(),timezone,now(),'x','m','p',array['context_note'],0,pg_temp.ps_source('n')) from ps_fixture$$,'23503',null,'mismatched patient rejected by composite foreign key');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','99999999-9999-9999-9999-999999999999',true);
select is((select count(*) from public.period_summary_context((select org from ps_fixture),(select episode from ps_fixture))),0::bigint,'identity without profile has no context');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'x','m','p',array['context_note'],0,pg_temp.ps_source('n')) from ps_fixture$$,'42501',null,'identity without profile cannot save');
reset role;
set local role anon;
select throws_ok($$select public.period_summary_context((select org from ps_fixture),(select episode from ps_fixture))$$,'42501',null,'anonymous context call denied at runtime');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'x','m','p',array['context_note'],0,pg_temp.ps_source('n')) from ps_fixture$$,'42501',null,'anonymous save call denied at runtime');
reset role;

create temporary table ps_actor_roles as
select distinct r.organization_id,r.id role_id from public.role_assignments ra
join public.organization_memberships m on m.id=ra.membership_id join public.profiles p on p.id=m.profile_id
join public.roles r on r.id=ra.role_id where p.auth_user_id='11111111-1111-1111-1111-111111111111';
delete from public.role_permissions rp using ps_actor_roles ar where rp.organization_id=ar.organization_id and rp.role_id=ar.role_id and rp.permission_code='clinical.summary.use';
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select is((select count(*) from public.period_summaries),0::bigint,'summary permission revocation hides author history immediately');
select is((select count(*) from public.period_summary_context((select org from ps_fixture),(select episode from ps_fixture))),0::bigint,'summary permission revocation hides context');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'x','m','p',array['context_note'],0,pg_temp.ps_source('n')) from ps_fixture$$,'42501',null,'summary permission revocation denies save');
reset role;
insert into public.role_permissions(organization_id,role_id,permission_code) select organization_id,role_id,'clinical.summary.use' from ps_actor_roles on conflict do nothing;
delete from public.role_permissions rp using ps_actor_roles ar where rp.organization_id=ar.organization_id and rp.role_id=ar.role_id and rp.permission_code='context.note.read';
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select is((select count(*) from public.period_summaries),0::bigint,'source permission revocation hides own history');
select is((select count(*) from public.period_summary_context((select org from ps_fixture),(select episode from ps_fixture))),0::bigint,'source permission revocation hides context');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'x','m','p',array['context_note'],0,pg_temp.ps_source('n')) from ps_fixture$$,'42501',null,'source permission revocation denies save');
reset role;
insert into public.role_permissions(organization_id,role_id,permission_code) select organization_id,role_id,'context.note.read' from ps_actor_roles on conflict do nothing;

create temporary table ps_assignment as select id from public.care_assignments where hospitalization_id=(select episode from ps_fixture) and membership_id=(select m.id from public.profiles p join public.organization_memberships m on m.profile_id=p.id where p.auth_user_id='11111111-1111-1111-1111-111111111111');
update public.care_assignments set valid_until=now()-interval '1 second' where id in (select id from ps_assignment);
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select is((select count(*) from public.period_summaries),0::bigint,'assignment revocation hides own history');
select is((select count(*) from public.period_summary_context((select org from ps_fixture),(select episode from ps_fixture))),0::bigint,'assignment revocation hides context');
select throws_ok($$select public.save_period_summary(gen_random_uuid(),org,episode,patient,now()-interval '2 hours',now(),timezone,now(),'x','m','p',array['context_note'],0,pg_temp.ps_source('n')) from ps_fixture$$,'42501',null,'assignment revocation denies save');
reset role;
update public.care_assignments set valid_until=null where id in (select id from ps_assignment);

select * from finish();
rollback;
