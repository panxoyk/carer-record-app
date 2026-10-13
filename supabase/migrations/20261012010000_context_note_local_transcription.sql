-- Bitácora milestones become local-ASR notes (ADR-016): the audio and its raw
-- transcription are local technical artifacts that never leave the device, so
-- the stored-audio provision of ADR-015 is withdrawn. The only row that reaches
-- the server is the note its author reviewed and confirmed, and it carries
-- auditable non-sensitive provenance instead of an audio object.
--
-- Additive on top of 20261012000000_context_note_milestones.sql, which is not
-- edited: every removal below is a drop performed here.

-- The timeline projection exposes the audio object path and duration. It is
-- rebuilt at the end of this migration, so drop it before the columns go away.
drop view if exists public.clinical_timeline_by_hospitalization;

alter table public.context_notes
  add column transcription_metadata jsonb;

-- ADR-016 decision 3: provenance is auditable metadata, never content. The
-- contract is enforced here so no client can smuggle transcribed text into a
-- jsonb column, whatever the app does.
create or replace function private.is_asr_transcription_metadata(p_metadata jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select
    p_metadata is null
    or (
      jsonb_typeof(p_metadata) = 'object'
      and octet_length(p_metadata::text) <= 4096
      and (
        p_metadata - array[
          'asr_engine', 'asr_model', 'asr_model_version', 'asr_model_checksum',
          'asr_parameters', 'duration_ms', 'mean_confidence',
          'low_confidence_segments', 'pipeline_version'
        ]
      ) = '{}'::jsonb
      and p_metadata ? 'asr_engine'
      and p_metadata ? 'pipeline_version'
      and not exists (
        select 1
        from jsonb_each(p_metadata) as entry(key, value)
        where entry.key in (
          'asr_engine', 'asr_model', 'asr_model_version',
          'asr_model_checksum', 'pipeline_version'
        )
          and case
            when jsonb_typeof(entry.value) <> 'string' then true
            else entry.value #>> '{}' !~ '^[A-Za-z0-9._:+/-]{1,128}$'
          end
      )
      and not exists (
        select 1
        from jsonb_each(p_metadata) as entry(key, value)
        where entry.key in ('duration_ms', 'mean_confidence')
          and jsonb_typeof(entry.value) <> 'number'
      )
      and not exists (
        select 1
        from jsonb_each(p_metadata) as entry(key, value)
        where entry.key = 'asr_parameters'
          and case
            when jsonb_typeof(entry.value) <> 'object' then true
            else exists (
              select 1
              from jsonb_each(entry.value) as parameter(key, value)
              where case
                when jsonb_typeof(parameter.value) = 'number' then false
                when jsonb_typeof(parameter.value) = 'boolean' then false
                when jsonb_typeof(parameter.value) = 'string'
                  then parameter.value #>> '{}' !~ '^[A-Za-z0-9._:+/-]{1,128}$'
                else true
              end
            )
          end
      )
      and not exists (
        select 1
        from jsonb_each(p_metadata) as entry(key, value)
        where entry.key = 'low_confidence_segments'
          and case
            when jsonb_typeof(entry.value) <> 'array' then true
            when jsonb_array_length(entry.value) > 200 then true
            else exists (
              select 1
              from jsonb_array_elements(entry.value) as segment(value)
              where case
                when jsonb_typeof(segment.value) <> 'object' then true
                else exists (
                  select 1
                  from jsonb_each(segment.value) as field(key, value)
                  where field.key not in ('start_ms', 'end_ms', 'confidence')
                    or jsonb_typeof(field.value) <> 'number'
                )
              end
            )
          end
      )
    )
$$;

comment on function private.is_asr_transcription_metadata(jsonb) is
  'True when jsonb is null or an ASR provenance object built only from the keys allowed by ADR-016, with bounded identifier strings and no free text, so milestone provenance can never carry transcribed content.';

revoke all on function private.is_asr_transcription_metadata(jsonb)
  from public, anon;
-- A CHECK constraint is evaluated with the privileges of the inserting role, so
-- the runtime roles need EXECUTE on this predicate. It is a pure function of its
-- argument: it reads no row and grants no access.
grant execute on function private.is_asr_transcription_metadata(jsonb)
  to authenticated, service_role;

alter table public.context_notes
  add constraint context_notes_transcription_metadata_shape
    check (private.is_asr_transcription_metadata(transcription_metadata));

-- ADR-016 decision 2: an audio milestone only exists once its author confirms
-- text, so `content` is mandatory for both forms and the metadata replaces the
-- audio object as the audit trail. Text milestones keep no metadata.
alter table public.context_notes
  drop constraint context_notes_single_form;

alter table public.context_notes
  add constraint context_notes_single_form
    check (
      (input_method = 'text'
        and content is not null
        and btrim(content) <> ''
        and transcription_metadata is null)
      or (input_method = 'audio'
        and content is not null
        and btrim(content) <> ''
        and transcription_metadata is not null)
    );

-- ADR-016 decision 1: no column may carry audio to the server.
alter table public.context_notes drop column storage_path;
alter table public.context_notes drop column audio_duration_ms;

comment on table public.context_notes is
  'Bitácora milestones authored by an active member for an accessible hospitalization; confirmed rows project into the clinical timeline view. Audio milestones store the text their author confirmed plus non-sensitive transcription provenance; the audio and its raw transcription never leave the device (ADR-016). No update/delete grants in this slice.';

-- The local stack applies default table privileges that grant ALL to
-- authenticated, so the column-limited contract is restated explicitly with the
-- new provenance column in place of the withdrawn audio columns.
revoke all on public.context_notes from public, anon, authenticated, service_role;
grant select (id, organization_id, hospitalization_id, patient_id, input_method,
  content, transcription_metadata, status, occurred_at, created_at)
  on public.context_notes to authenticated;
grant insert (organization_id, hospitalization_id, patient_id, input_method,
  content, transcription_metadata, client_event_id)
  on public.context_notes to authenticated;

-- Withdraw the stored-audio provision of ADR-015 in full: policies first, then
-- the helpers they call, then the objects, then the bucket itself.
drop policy if exists "authorized authors store milestone audio" on storage.objects;
drop policy if exists "authorized members read milestone audio" on storage.objects;

drop function if exists public.can_store_context_note_audio(text);
drop function if exists public.can_read_context_note_audio(text);

-- Storage blocks direct table deletion through storage.protect_delete(); the
-- guard is a session flag meant for interactive maintenance, and here it is
-- scoped to the single bucket being withdrawn.
set storage.allow_delete_query = 'true';
delete from storage.objects where bucket_id = 'context-note-audio';
delete from storage.buckets where id = 'context-note-audio';

-- The timeline keeps mixing clinical events with confirmed milestones and keeps
-- security_invoker/security_barrier. `summary` is now the confirmed content for
-- both forms, and the audio columns are gone: provenance stays in
-- context_notes.transcription_metadata and is not projected to every reader.
create or replace view public.clinical_timeline_by_hospitalization
with (security_invoker = true, security_barrier = true) as
select e.organization_id, e.hospitalization_id, e.id as event_id,
       e.kind::text, e.occurred_at, e.summary,
       e.patient_id, e.created_at,
       'clinical_event' as source_kind
from public.clinical_events e
union all
select n.organization_id, n.hospitalization_id, n.id,
       case when n.input_method = 'audio' then 'milestone_audio' else 'milestone' end,
       n.occurred_at,
       n.content,
       n.patient_id, n.created_at,
       'context_note'
from public.context_notes n
where n.status = 'confirmed';

revoke all on public.clinical_timeline_by_hospitalization from public, anon;
grant select on public.clinical_timeline_by_hospitalization to authenticated;

comment on view public.clinical_timeline_by_hospitalization is
  'Typed episode timeline mixing clinical events and confirmed bitácora milestones; invoker grants and base-table RLS apply. milestone_audio summaries are the text their author confirmed after local transcription; audio, raw transcription and provenance details stay in context_notes and are not projected here.';