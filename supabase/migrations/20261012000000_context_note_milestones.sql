-- Bitácora milestones (context notes): user-authored timeline entries in text
-- or stored-audio form. RLS is the authorization authority: active
-- profile/membership, context.note.* permissions and episode scope are all
-- checked server-side. Raw milestone audio lives in the private
-- 'context-note-audio' bucket under <hospitalization_id>/<client_event_id>.m4a
-- with matching storage policies. Transcription of that audio is a future
-- on-device capability (ADR-015); nothing in this slice sends it anywhere.

create table public.context_notes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations (id),
  hospitalization_id uuid not null,
  patient_id uuid not null,
  author_id uuid not null default auth.uid(),
  status text not null default 'confirmed'
    check (status in ('draft', 'confirmed')),
  input_method text not null
    check (input_method in ('text', 'audio')),
  content text
    check (content is null or char_length(content) <= 20000),
  storage_path text
    check (storage_path is null or (btrim(storage_path) <> '' and char_length(storage_path) <= 512)),
  audio_duration_ms integer
    check (audio_duration_ms is null or audio_duration_ms >= 0),
  client_event_id uuid not null,
  occurred_at timestamptz not null default now(),
  confirmed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint context_notes_episode_patient_tenant_fk
    foreign key (organization_id, hospitalization_id, patient_id)
    references public.hospitalizations (organization_id, id, patient_id)
    on delete restrict,
  constraint context_notes_single_form
    check (
      (input_method = 'text' and content is not null and btrim(content) <> '' and storage_path is null)
      or (input_method = 'audio' and storage_path is not null and btrim(storage_path) <> '')
    ),
  constraint context_notes_client_event_unique
    unique (organization_id, client_event_id)
);

create index context_notes_episode_timeline_idx
  on public.context_notes (organization_id, hospitalization_id, occurred_at desc, id);

comment on table public.context_notes is
  'Bitácora milestones authored by an active member for an accessible hospitalization; confirmed rows project into the clinical timeline view. Text keeps content; audio keeps a private bucket object path and duration. No update/delete grants in this slice.';

alter table public.context_notes enable row level security;

create or replace function private.can_write_context_note(
  p_organization_id uuid,
  p_hospitalization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.has_active_iam_permission(p_organization_id, 'context.note.create')
    and public.has_active_iam_permission(p_organization_id, 'context.note.confirm')
    and private.can_read_clinical_hospitalization(
      p_organization_id, p_hospitalization_id, 'context.note.read'
    )
$$;

create or replace function private.can_read_context_note(
  p_organization_id uuid,
  p_hospitalization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.has_active_iam_permission(p_organization_id, 'context.note.read')
    and private.can_read_clinical_hospitalization(
      p_organization_id, p_hospitalization_id, 'context.note.read'
    )
$$;

revoke all on function private.can_write_context_note(uuid, uuid) from public, anon;
grant execute on function private.can_write_context_note(uuid, uuid) to authenticated;
revoke all on function private.can_read_context_note(uuid, uuid) from public, anon;
grant execute on function private.can_read_context_note(uuid, uuid) to authenticated;

create policy "author publishes own context note milestones"
  on public.context_notes for insert to authenticated
  with check (
    author_id = auth.uid()
    and private.can_write_context_note(organization_id, hospitalization_id)
  );

create policy "authors read own rows; members read confirmed milestones"
  on public.context_notes for select to authenticated
  using (
    author_id = auth.uid()
    or (status = 'confirmed'
        and private.can_read_context_note(organization_id, hospitalization_id))
  );

-- Storage: raw milestone audio stays private, one object per milestone under
-- the hospitalization folder, readable only by members with episode scope.
insert into storage.buckets (id, name, public)
values ('context-note-audio', 'context-note-audio', false)
on conflict (id) do nothing;

create or replace function public.can_store_context_note_audio(p_hospitalization_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_hospitalization_id ~ '^[0-9a-fA-F-]{36}$'
    and exists (
      select 1
      from public.hospitalizations h
      where h.id = p_hospitalization_id::uuid
        and public.has_active_iam_permission(h.organization_id, 'context.note.create')
        and public.has_active_iam_permission(h.organization_id, 'context.note.confirm')
        and private.can_read_clinical_hospitalization(h.organization_id, h.id, 'context.note.read')
    )
$$;

create or replace function public.can_read_context_note_audio(p_hospitalization_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_hospitalization_id ~ '^[0-9a-fA-F-]{36}$'
    and exists (
      select 1
      from public.hospitalizations h
      where h.id = p_hospitalization_id::uuid
        and public.has_active_iam_permission(h.organization_id, 'context.note.read')
        and private.can_read_clinical_hospitalization(h.organization_id, h.id, 'context.note.read')
    )
$$;

revoke all on function public.can_store_context_note_audio(text) from public, anon;
grant execute on function public.can_store_context_note_audio(text) to authenticated;
revoke all on function public.can_read_context_note_audio(text) from public, anon;
grant execute on function public.can_read_context_note_audio(text) to authenticated;

create policy "authorized authors store milestone audio"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'context-note-audio'
    and public.can_store_context_note_audio((storage.foldername(name))[1])
  );

create policy "authorized members read milestone audio"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'context-note-audio'
    and public.can_read_context_note_audio((storage.foldername(name))[1])
  );

-- The local stack applies default table privileges that grant ALL to
-- authenticated, so the column-limited contract must be stated explicitly:
-- read without author_id, insert without id/status timestamps; no
-- update/delete/truncate for any runtime role.
revoke all on public.context_notes from public, anon, authenticated, service_role;
grant select (id, organization_id, hospitalization_id, patient_id, input_method,
  content, storage_path, audio_duration_ms, status, occurred_at, created_at)
  on public.context_notes to authenticated;
grant insert (organization_id, hospitalization_id, patient_id, input_method,
  content, storage_path, audio_duration_ms, client_event_id)
  on public.context_notes to authenticated;

-- The episode timeline now mixes clinical events with confirmed milestones.
-- source_kind identifies the origin; audio columns are only populated for
-- stored-audio milestones.
-- The previous view is dropped because kind widens from clinical_event_kind
-- to text (milestones introduce non-clinical kinds); all consumers read the
-- same column names.
drop view if exists public.clinical_timeline_by_hospitalization;
create or replace view public.clinical_timeline_by_hospitalization
with (security_invoker = true, security_barrier = true) as
select e.organization_id, e.hospitalization_id, e.id as event_id,
       e.kind::text, e.occurred_at, e.summary,
       e.patient_id, e.created_at,
       'clinical_event' as source_kind,
       null::text as audio_storage_path,
       null::integer as audio_duration_ms
from public.clinical_events e
union all
select n.organization_id, n.hospitalization_id, n.id,
       case when n.input_method = 'audio' then 'milestone_audio' else 'milestone' end,
       n.occurred_at,
       case when n.input_method = 'audio' then 'Hito de audio' else n.content end,
       n.patient_id, n.created_at,
       'context_note',
       case when n.input_method = 'audio' then n.storage_path else null end,
       n.audio_duration_ms
from public.context_notes n
where n.status = 'confirmed';

revoke all on public.clinical_timeline_by_hospitalization from public, anon;
grant select on public.clinical_timeline_by_hospitalization to authenticated;

comment on view public.clinical_timeline_by_hospitalization is
  'Typed episode timeline mixing clinical events and confirmed bitácora milestones; invoker grants and base-table RLS apply. audio_storage_path/audio_duration_ms identify stored-audio milestones; raw payload and provenance remain private.';
