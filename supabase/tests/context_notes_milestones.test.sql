begin;
create extension if not exists pgtap;
select plan(35);

-- Structure and privileges.
select ok(
  (select relrowsecurity from pg_class where oid='public.context_notes'::regclass)
  and not has_table_privilege('authenticated','public.context_notes','update')
  and not has_table_privilege('authenticated','public.context_notes','delete')
  and not has_table_privilege('authenticated','public.context_notes','truncate'),
  'context_notes is RLS-enabled without runtime DML grants'
);
select ok(
  has_column_privilege('authenticated','public.context_notes','client_event_id','insert')
  and has_column_privilege('authenticated','public.context_notes','content','select')
  and has_column_privilege('authenticated','public.context_notes','transcription_metadata','select')
  and not has_column_privilege('authenticated','public.context_notes','author_id','insert')
  and not has_column_privilege('authenticated','public.context_notes','status','insert'),
  'authenticated can insert and read context notes through the column contract'
);
select ok(
  not has_table_privilege('anon','public.context_notes','select')
  and not has_table_privilege('anon','public.context_notes','insert')
  and not has_table_privilege('service_role','public.context_notes','update')
  and not has_table_privilege('service_role','public.context_notes','delete'),
  'anon and service_role have no context-note DML bypass'
);
select ok(
  not has_column_privilege('authenticated','public.context_notes','author_id','select')
  and has_column_privilege('authenticated','public.context_notes','content','select'),
  'milestone author stays private while content is readable'
);
select ok((select reloptions @> array['security_invoker=true','security_barrier=true']
  from pg_class where oid='public.clinical_timeline_by_hospitalization'::regclass),
  'timeline view remains invoker-security and barrier'
);

-- Privacy contract of ADR-016: nothing in the schema can carry audio. These
-- assertions are what keep the withdrawn provision of ADR-015 withdrawn, and
-- they fail if a bucket, policy, helper or column comes back.
select ok(
  (select count(*) from storage.buckets where id='context-note-audio')=0,
  'the stored-audio bucket of ADR-015 no longer exists'
);
select ok(
  not exists (
    select 1 from pg_policies
    where schemaname='storage' and tablename='objects'
      and (qual like '%context-note-audio%' or with_check like '%context-note-audio%')
  ),
  'no storage.objects policy references the withdrawn audio bucket'
);
select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema='public'
      and (column_name like '%audio%' or column_name in ('storage_path'))
  )
  and not exists (
    select 1 from information_schema.columns
    where table_schema='public'
      and column_name like 'transcri%' and column_name <> 'transcription_metadata'
  ),
  'no public column can transport an audio object or a raw transcription'
);
select ok(
  to_regprocedure('public.can_store_context_note_audio(text)') is null
    and to_regprocedure('public.can_read_context_note_audio(text)') is null,
  'the stored-audio authorization helpers are removed'
);

-- Fixtures: the seeded demo episodes (assigned to the clinician, assigned to a
-- colleague who is also assigned to the clinician, and out of the clinician's
-- scope) plus an isolated second tenant.
create temporary table cnm_fixture as
select o.id as organization_id,
       h1.id as assigned_episode, h1.patient_id as assigned_patient,
       h2.id as other_episode, h2.patient_id as other_patient,
       h3.id as shared_episode, h3.patient_id as shared_patient
from public.hospitalizations h1
cross join public.hospitalizations h2
cross join public.hospitalizations h3
join public.organizations o on o.id = h1.organization_id
where h1.id='a1000000-0000-0000-0000-000000000001'
  and h2.id='a1000000-0000-0000-0000-000000000003'
  and h3.id='a1000000-0000-0000-0000-000000000008';

-- The fixture lives in the runner's temporary schema; let the authenticated
-- role read it for the RLS-positive inserts (values stay synthetic).
grant select on table cnm_fixture to authenticated;

insert into public.organizations (id, slug, display_name)
values ('c2000000-0000-0000-0000-000000000001','cnm-other','CNM other tenant');
insert into public.patients (id, organization_id, given_name, family_name)
values ('c2000000-0000-0000-0000-000000000002','c2000000-0000-0000-0000-000000000001','Synthetic','Other');
insert into public.hospitalizations (id, organization_id, patient_id, status, admitted_at)
values ('c2000000-0000-0000-0000-000000000003','c2000000-0000-0000-0000-000000000001',
  'c2000000-0000-0000-0000-000000000002','admitted',now());

-- A draft owned by the seeded clinician on the shared episode. Runtime roles
-- cannot set status or author_id, so the runner creates it directly to exercise
-- the read policy against a colleague who legitimately reads that episode.
insert into public.context_notes (
  id, organization_id, hospitalization_id, patient_id, author_id, status,
  input_method, content, client_event_id)
select 'c1000000-0000-0000-0000-0000000000f0', organization_id, shared_episode,
  shared_patient, '11111111-1111-1111-1111-111111111111', 'draft', 'text',
  'Borrador sintético todavía sin confirmar.', 'c1000000-0000-0000-0000-0000000000f1'
from cnm_fixture;

-- Assigned clinician (seeded physician) publishes both milestone forms.
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select lives_ok($$
  insert into public.context_notes (organization_id, hospitalization_id, patient_id,
    input_method, content, client_event_id)
  select organization_id, assigned_episode, assigned_patient, 'text',
    'Hito de prueba: control sintético sin cambios.',
    'c1000000-0000-0000-0000-000000000001'
  from cnm_fixture
$$, 'assigned clinician inserts a text milestone');
select lives_ok($$
  insert into public.context_notes (organization_id, hospitalization_id, patient_id,
    input_method, content, transcription_metadata, client_event_id)
  select organization_id, assigned_episode, assigned_patient, 'audio',
    'Paciente refiere mejoría tras la medication sintética.',
    '{"asr_engine":"sherpa_onnx","asr_model":"es-small","asr_model_version":"2026-10",
      "asr_model_checksum":"a1b2c3d4","duration_ms":42000,"mean_confidence":0.91,
      "low_confidence_segments":[{"start_ms":12000,"end_ms":13500,"confidence":0.42}],
      "asr_parameters":{"beam_size":5,"num_threads":2},"pipeline_version":"1.0.0"}'::jsonb,
    'c1000000-0000-0000-0000-000000000002'
  from cnm_fixture
$$, 'assigned clinician inserts a confirmed audio milestone with provenance');
select lives_ok($$
  insert into public.context_notes (organization_id, hospitalization_id, patient_id,
    input_method, content, client_event_id)
  select organization_id, shared_episode, shared_patient, 'text',
    'Hito compartido con un colega asignado al mismo episodio.',
    'c1000000-0000-0000-0000-000000000012'
  from cnm_fixture
$$, 'the clinician publishes on an episode a colleague also reads');
select throws_ok($$
  insert into public.context_notes (organization_id, hospitalization_id, patient_id,
    input_method, content, client_event_id)
  select organization_id, assigned_episode, assigned_patient, 'text', 'Otro texto.',
    'c1000000-0000-0000-0000-000000000001'
  from cnm_fixture
$$, '23505', null, 'replaying the same client_event_id does not duplicate');
select throws_ok($$
  insert into public.context_notes (organization_id, hospitalization_id, patient_id,
    input_method, content, client_event_id)
  select organization_id, other_episode, other_patient, 'text', 'Fuera de alcance.',
    'c1000000-0000-0000-0000-000000000003'
  from cnm_fixture
$$, '42501', null, 'milestone outside the current care assignment is denied');
select throws_ok($$
  insert into public.context_notes (organization_id, hospitalization_id, patient_id,
    input_method, content, client_event_id)
  values ('c2000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000003',
    'c2000000-0000-0000-0000-000000000002','text','Otro tenant.',
    'c1000000-0000-0000-0000-000000000004')
$$, '42501', null, 'milestone for another tenant is denied');
select throws_ok($$
  insert into public.context_notes (organization_id, hospitalization_id, patient_id,
    input_method, content, transcription_metadata, client_event_id)
  select organization_id, assigned_episode, assigned_patient, 'audio',
    'Texto confirmado sin procedencia.', null,
    'c1000000-0000-0000-0000-000000000005'
  from cnm_fixture
$$, '23514', null, 'audio milestone without transcription metadata is rejected');
select throws_ok($$
  insert into public.context_notes (organization_id, hospitalization_id, patient_id,
    input_method, transcription_metadata, client_event_id)
  select organization_id, assigned_episode, assigned_patient, 'audio',
    '{"asr_engine":"sherpa_onnx","pipeline_version":"1.0.0"}'::jsonb,
    'c1000000-0000-0000-0000-000000000006'
  from cnm_fixture
$$, '23514', null, 'audio milestone without confirmed content is rejected');
select throws_ok($$
  insert into public.context_notes (organization_id, hospitalization_id, patient_id,
    input_method, content, transcription_metadata, client_event_id)
  select organization_id, assigned_episode, assigned_patient, 'text',
    'Hito de texto con procedencia.',
    '{"asr_engine":"sherpa_onnx","pipeline_version":"1.0.0"}'::jsonb,
    'c1000000-0000-0000-0000-00000000000e'
  from cnm_fixture
$$, '23514', null, 'text milestone cannot carry transcription metadata');
select throws_ok($$
  insert into public.context_notes (organization_id, hospitalization_id, patient_id,
    input_method, content, transcription_metadata, client_event_id)
  select organization_id, assigned_episode, assigned_patient, 'audio',
    'Texto confirmado.', '["sherpa_onnx"]'::jsonb,
    'c1000000-0000-0000-0000-00000000000f'
  from cnm_fixture
$$, '23514', null, 'transcription metadata that is not an object is rejected');
select throws_ok($$
  insert into public.context_notes (organization_id, hospitalization_id, patient_id,
    input_method, content, transcription_metadata, client_event_id)
  select organization_id, assigned_episode, assigned_patient, 'audio',
    'Texto confirmado.',
    ('{"asr_engine":"sherpa_onnx","pipeline_version":"1.0.0","transcript":"' ||
      repeat('a', 5000) || '"}')::jsonb,
    'c1000000-0000-0000-0000-000000000010'
  from cnm_fixture
$$, '23514', null, 'oversized transcription metadata is rejected');
select throws_ok($$
  insert into public.context_notes (organization_id, hospitalization_id, patient_id,
    input_method, content, transcription_metadata, client_event_id)
  select organization_id, assigned_episode, assigned_patient, 'audio',
    'Texto confirmado.',
    '{"asr_engine":"sherpa_onnx","pipeline_version":"1.0.0",
      "asr_parameters":{"notes":"el paciente refiere mejora clinica"}}'::jsonb,
    'c1000000-0000-0000-0000-000000000011'
  from cnm_fixture
$$, '23514', null, 'transcription metadata cannot hide free text in a parameter');
select throws_ok($$
  update public.context_notes set content='editado'
  where client_event_id='c1000000-0000-0000-0000-000000000001'
$$, '42501', null, 'published milestones cannot be updated');
select throws_ok($$
  delete from public.context_notes
  where client_event_id='c1000000-0000-0000-0000-000000000002'
$$, '42501', null, 'published milestones cannot be deleted');
reset role;

select is(
  (select count(*) from public.context_notes
    where author_id='11111111-1111-1111-1111-111111111111' and status='confirmed'),
  3::bigint, 'every milestone is confirmed and authored by the seeded clinician');

set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select is(
  (select count(content) from public.context_notes
    where content like 'Borrador sintético%'),
  1::bigint, 'the author reads their own draft through the select policy');
select is(
  (select count(*) from public.clinical_timeline_by_hospitalization
    where hospitalization_id='a1000000-0000-0000-0000-000000000001'
      and source_kind='context_note'
      and ((kind='milestone' and summary='Hito de prueba: control sintético sin cambios.')
        or (kind='milestone_audio'
          and summary='Paciente refiere mejoría tras la medication sintética.'))),
  2::bigint, 'the timeline projects both milestone forms as confirmed text');
select ok(
  (select summary from public.clinical_timeline_by_hospitalization
    where hospitalization_id='a1000000-0000-0000-0000-000000000001'
      and kind='milestone_audio') <> 'Hito de audio',
  'audio milestones no longer collapse to a placeholder summary'
);
select is(
  (select count(*) from public.clinical_timeline_by_hospitalization
    where hospitalization_id='a1000000-0000-0000-0000-000000000008'
      and source_kind='context_note'),
  1::bigint, 'the timeline projects confirmed milestones only, never drafts');
reset role;

-- Administrator reads the milestones. It holds the full context.note.* set
-- (delegation rule 20261011300000); the write-denial case below uses a role-less
-- member instead.
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-3333-3333-333333333333',true);
select is(
  (select count(*) from public.clinical_timeline_by_hospitalization
    where hospitalization_id='a1000000-0000-0000-0000-000000000001'
      and source_kind='context_note'),
  2::bigint, 'administrator with context.note.read sees the milestones');
reset role;

-- Author isolation on an episode both members are assigned to: the colleague
-- reads the confirmed milestone but never the other author's draft.
set local role authenticated;
select set_config('request.jwt.claim.sub','22222222-2222-2222-2222-222222222222',true);
select is(
  (select count(content) from public.context_notes
    where content like 'Borrador sintético%'),
  0::bigint, 'another author cannot read a draft owned by someone else');
select is(
  (select count(*) from public.clinical_timeline_by_hospitalization
    where hospitalization_id='a1000000-0000-0000-0000-000000000008'
      and source_kind='context_note'),
  1::bigint, 'the colleague still reads confirmed milestones of the same episode');
reset role;

-- Suspended and role-less members are denied end to end.
set local role authenticated;
select set_config('request.jwt.claim.sub','55555555-5555-5555-5555-555555555555',true);
select throws_ok($$
  insert into public.context_notes (organization_id, hospitalization_id, patient_id,
    input_method, content, client_event_id)
  select organization_id, assigned_episode, assigned_patient, 'text', 'Suspendida.',
    'c1000000-0000-0000-0000-00000000000a'
  from cnm_fixture
$$, '42501', null, 'suspended profile cannot publish milestones');
select is(
  (select count(*) from public.clinical_timeline_by_hospitalization
    where hospitalization_id='a1000000-0000-0000-0000-000000000001'
      and source_kind='context_note'),
  0::bigint, 'suspended profile sees no milestones');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','44444444-4444-4444-4444-444444444444',true);
select throws_ok($$
  insert into public.context_notes (organization_id, hospitalization_id, patient_id,
    input_method, content, client_event_id)
  select organization_id, assigned_episode, assigned_patient, 'text', 'Sin rol.',
    'c1000000-0000-0000-0000-00000000000b'
  from cnm_fixture
$$, '42501', null, 'member without clinical roles cannot publish milestones');
select is(
  (select count(*) from public.clinical_timeline_by_hospitalization
    where hospitalization_id='a1000000-0000-0000-0000-000000000001'),
  0::bigint, 'member without clinical roles sees no timeline');
reset role;

select * from finish();
rollback;