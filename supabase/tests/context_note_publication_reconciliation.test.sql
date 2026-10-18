begin;
create extension if not exists pgtap;
select plan(13);

create temporary table cnpr_fixture as
select o.id organization_id, h.id hospitalization_id, h.patient_id
from public.organizations o
join public.hospitalizations h on h.organization_id = o.id
where h.id = 'a1000000-0000-0000-0000-000000000001';
grant select on cnpr_fixture to authenticated;

insert into public.context_notes (organization_id, hospitalization_id, patient_id, author_id,
  input_method, content, client_event_id)
select organization_id, hospitalization_id, patient_id,
  '11111111-1111-1111-1111-111111111111', 'text', 'Confirmed reconciliation text',
  'd1000000-0000-0000-0000-000000000001' from cnpr_fixture;
insert into public.context_notes (organization_id, hospitalization_id, patient_id, author_id,
  input_method, content, transcription_metadata, client_event_id)
select organization_id, hospitalization_id, patient_id,
  '11111111-1111-1111-1111-111111111111', 'audio', 'Confirmed audio text',
  '{"asr_engine":"sherpa_onnx","pipeline_version":"1.0"}'::jsonb,
  'd1000000-0000-0000-0000-000000000002' from cnpr_fixture;
insert into public.context_notes (organization_id, hospitalization_id, patient_id, author_id,
  status, input_method, content, client_event_id)
select organization_id, hospitalization_id, patient_id,
  '11111111-1111-1111-1111-111111111111', 'draft', 'text', 'Draft text',
  'd1000000-0000-0000-0000-000000000003' from cnpr_fixture;

set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select ok(public.context_note_publication_matches(f.organization_id, f.hospitalization_id,
  f.patient_id, 'text', ' Confirmed reconciliation text ', null,
  'd1000000-0000-0000-0000-000000000001'), 'matches canonical trimmed confirmed text')
from cnpr_fixture f;
select ok(public.context_note_publication_matches(f.organization_id, f.hospitalization_id,
  f.patient_id, 'audio', 'Confirmed audio text',
  '{"asr_engine":"sherpa_onnx","pipeline_version":"1.0"}'::jsonb,
  'd1000000-0000-0000-0000-000000000002'), 'matches exact audio payload metadata')
from cnpr_fixture f;
select is((select count(*) from public.context_notes), 3::bigint, 'reconciliation did not insert a row');
select ok(not public.context_note_publication_matches(f.organization_id, f.hospitalization_id,
  f.patient_id, 'text', 'Different text', null,
  'd1000000-0000-0000-0000-000000000001'), 'content mismatch is false') from cnpr_fixture f;
select ok(not public.context_note_publication_matches(f.organization_id, f.hospitalization_id,
  f.patient_id, 'audio', 'Confirmed audio text', null,
  'd1000000-0000-0000-0000-000000000002'), 'metadata mismatch is false') from cnpr_fixture f;
select ok(not public.context_note_publication_matches(f.organization_id, f.hospitalization_id,
  f.patient_id, 'text', 'Missing', null,
  'd1000000-0000-0000-0000-000000000004'), 'missing id is false') from cnpr_fixture f;
select ok(not public.context_note_publication_matches(f.organization_id, f.hospitalization_id,
  f.patient_id, 'text', 'Draft text', null,
  'd1000000-0000-0000-0000-000000000003'), 'draft row is false') from cnpr_fixture f;
select ok(not public.context_note_publication_matches(f.organization_id, f.hospitalization_id,
  f.patient_id, 'text', 'Confirmed reconciliation text', null,
  'd1000000-0000-0000-0000-000000000099'), 'different event id is false') from cnpr_fixture f;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-3333-3333-333333333333',true);
select ok(not public.context_note_publication_matches(f.organization_id, f.hospitalization_id,
  f.patient_id, 'text', 'Confirmed reconciliation text', null,
  'd1000000-0000-0000-0000-000000000001'), 'another author receives false') from cnpr_fixture f;
select throws_ok($$ select public.context_note_publication_matches(
  'c2000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000003',
  'c2000000-0000-0000-0000-000000000002', 'text', 'x', null,
  'd1000000-0000-0000-0000-000000000005') $$, '42501', null,
  'unauthorized tenant is denied before probing');
reset role;
delete from public.role_permissions rp
using cnpr_fixture f
where rp.organization_id = f.organization_id
  and rp.permission_code = 'context.note.create';
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select throws_ok($$ select public.context_note_publication_matches(
  (select organization_id from cnpr_fixture),
  (select hospitalization_id from cnpr_fixture),
  (select patient_id from cnpr_fixture), 'text', 'Confirmed reconciliation text', null,
  'd1000000-0000-0000-0000-000000000001') $$, '42501', null,
  'previously authorized author is denied after current write permission is revoked');
reset role;

select ok(has_function_privilege('authenticated',
  'public.context_note_publication_matches(uuid,uuid,uuid,text,text,jsonb,uuid)', 'execute')
  and not has_function_privilege('anon',
  'public.context_note_publication_matches(uuid,uuid,uuid,text,text,jsonb,uuid)', 'execute')
  and not has_function_privilege('service_role',
  'public.context_note_publication_matches(uuid,uuid,uuid,text,text,jsonb,uuid)', 'execute'),
  'only authenticated can execute reconciliation');
select ok(not has_column_privilege('authenticated','public.context_notes','author_id','select')
  and not has_column_privilege('authenticated','public.context_notes','client_event_id','select'),
  'reconciliation adds no sensitive column SELECT privileges');
select * from finish();
rollback;
