begin;
create extension if not exists pgtap;
select plan(27);

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
select ok((select count(*) from storage.buckets
  where id='context-note-audio' and name='context-note-audio' and public is false)=1,
  'private milestone audio bucket exists'
);

-- Fixtures: the seeded demo episodes (assigned vs not assigned to the clinician)
-- plus an isolated second tenant.
create temporary table cnm_fixture as
select o.id as organization_id,
       h1.id as assigned_episode, h1.patient_id as assigned_patient,
       h2.id as other_episode, h2.patient_id as other_patient
from public.hospitalizations h1
cross join public.hospitalizations h2
join public.organizations o on o.id = h1.organization_id
where h1.id='a1000000-0000-0000-0000-000000000001'
  and h2.id='a1000000-0000-0000-0000-000000000003';

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

-- Assigned clinician (seeded physician) can publish both milestone forms.
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
    input_method, storage_path, audio_duration_ms, client_event_id)
  select organization_id, assigned_episode, assigned_patient, 'audio',
    assigned_episode || '/c1000000-0000-0000-0000-000000000002.m4a', 42000,
    'c1000000-0000-0000-0000-000000000002'
  from cnm_fixture
$$, 'assigned clinician inserts a stored-audio milestone');
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
    input_method, content, client_event_id)
  select organization_id, assigned_episode, assigned_patient, 'text', '',
    'c1000000-0000-0000-0000-000000000005'
  from cnm_fixture
$$, '23514', null, 'empty text content violates the single-form constraint');
select throws_ok($$
  insert into public.context_notes (organization_id, hospitalization_id, patient_id,
    input_method, audio_duration_ms, client_event_id)
  select organization_id, assigned_episode, assigned_patient, 'audio', 1000,
    'c1000000-0000-0000-0000-000000000006'
  from cnm_fixture
$$, '23514', null, 'audio milestone without storage path is rejected');
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
  2::bigint, 'both milestones are confirmed and authored by the seeded clinician');

set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select is(
  (select count(*) from public.clinical_timeline_by_hospitalization
    where hospitalization_id='a1000000-0000-0000-0000-000000000001'
      and source_kind='context_note'
      and ((kind='milestone' and summary='Hito de prueba: control sintético sin cambios.')
        or (kind='milestone_audio' and audio_storage_path is not null
            and audio_duration_ms=42000))),
  2::bigint, 'the timeline view projects both milestone forms with audio metadata');
select lives_ok($$
  insert into storage.objects (bucket_id, name, owner)
  select 'context-note-audio',
    assigned_episode || '/c1000000-0000-0000-000000000007.m4a',
    '11111111-1111-1111-1111-111111111111'
  from cnm_fixture
$$, 'authorized author can store milestone audio in the episode folder');
select throws_ok($$
  insert into storage.objects (bucket_id, name, owner)
  select 'context-note-audio',
    other_episode || '/c1000000-0000-0000-0000-000000000008.m4a',
    '11111111-1111-1111-1111-111111111111'
  from cnm_fixture
$$, '42501', null, 'storing audio outside the episode scope is denied');
reset role;

-- Administrator reads milestones and audio. It holds the full context.note.*
-- set (delegation rule 20261011300000), so the write-denial case below uses a
-- role-less member instead.
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-3333-3333-333333333333',true);
select is(
  (select count(*) from public.clinical_timeline_by_hospitalization
    where hospitalization_id='a1000000-0000-0000-0000-000000000001'
      and source_kind='context_note'),
  2::bigint, 'administrator with context.note.read sees the milestones');
select is(
  (select count(*) from storage.objects
    where bucket_id='context-note-audio'
      and name like 'a1000000-0000-0000-0000-000000000001/c1000000-0000-0000-000000000007.m4a'),
  1::bigint, 'administrator can read the stored milestone audio object');
-- storage.objects keeps broad table grants in this stack; immutability comes
-- from RLS: no UPDATE/DELETE policy exists, so no row is mutable.
select ok(
  (select relrowsecurity from pg_class where oid='storage.objects'::regclass)
  and not exists (
    select 1 from pg_policies
    where schemaname='storage' and tablename='objects'
      and cmd in ('UPDATE','DELETE')
  ),
  'no RLS policy permits modifying or deleting stored audio objects'
);
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
select throws_ok($$
  insert into storage.objects (bucket_id, name, owner)
  values ('context-note-audio',
    'a1000000-0000-0000-0000-000000000001/c1000000-0000-0000-000000000009.m4a',
    '44444444-4444-4444-4444-444444444444')
$$, '42501', null, 'member without context.note.create cannot store audio');
select is(
  (select count(*) from public.clinical_timeline_by_hospitalization
    where hospitalization_id='a1000000-0000-0000-0000-000000000001'),
  0::bigint, 'member without clinical roles sees no timeline');
reset role;

select * from finish();
rollback;
