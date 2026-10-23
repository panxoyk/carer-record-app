-- Keep publication replay safe after episode closure: reading an existing note
-- is authorized independently from permission to publish a new one.
create or replace function public.context_note_publication_matches(
  p_organization_id uuid, p_hospitalization_id uuid, p_patient_id uuid,
  p_input_method text, p_content text, p_transcription_metadata jsonb, p_client_event_id uuid
)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null
    or not private.can_read_context_note(p_organization_id, p_hospitalization_id)
  then raise insufficient_privilege using message = 'permission denied'; end if;
  return exists (
    select 1 from public.context_notes n
    where n.organization_id = p_organization_id
      and n.hospitalization_id = p_hospitalization_id
      and n.patient_id = p_patient_id
      and n.input_method = p_input_method
      and n.content = pg_catalog.btrim(p_content)
      and n.transcription_metadata is not distinct from p_transcription_metadata
      and n.client_event_id = p_client_event_id
      and n.author_id = auth.uid() and n.status = 'confirmed'
  );
end $$;

-- Serialize new note insertion against a status transition. Locking the
-- hospitalization row makes the status check and INSERT mutually ordered.
create or replace function private.guard_context_note_episode_writable()
returns trigger language plpgsql security definer set search_path = '' as $$
declare episode_status text;
begin
  select h.status into episode_status from public.hospitalizations h
   where h.organization_id = new.organization_id and h.id = new.hospitalization_id
   for update;
  if episode_status not in ('admitted', 'temporarily_absent') then
    raise check_violation using message = 'hospitalization is closed for new notes';
  end if;
  return new;
end $$;
revoke all on function private.guard_context_note_episode_writable() from public, anon, authenticated, service_role;
create trigger context_notes_episode_writable
before insert on public.context_notes
for each row execute function private.guard_context_note_episode_writable();

alter table public.fhir_sources drop constraint if exists fhir_sources_logical_key_check;
alter table public.fhir_sources add constraint fhir_sources_logical_key_check
  check (logical_key ~ '^[A-Za-z0-9._-]{1,64}$');
alter table public.fhir_patient_links drop constraint if exists fhir_patient_links_fhir_id_check;
alter table public.fhir_patient_links add constraint fhir_patient_links_fhir_id_check
  check (fhir_id ~ '^[A-Za-z0-9.-]{1,64}$');
alter table public.fhir_encounter_links drop constraint if exists fhir_encounter_links_fhir_id_check;
alter table public.fhir_encounter_links add constraint fhir_encounter_links_fhir_id_check
  check (fhir_id ~ '^[A-Za-z0-9.-]{1,64}$');
alter table public.fhir_location_links drop constraint if exists fhir_location_links_fhir_id_check;
alter table public.fhir_location_links add constraint fhir_location_links_fhir_id_check
  check (fhir_id ~ '^[A-Za-z0-9.-]{1,64}$');
alter table public.fhir_location_links drop column location_id;

create or replace function public.fhir_authorized_encounter_context(p_organization_id uuid, p_hospitalization_id uuid, p_purpose text default 'record')
returns table(source_id uuid, patient_fhir_id text, encounter_fhir_id text, organization_id uuid, hospitalization_id uuid, patient_id uuid)
language plpgsql stable security definer set search_path = '' as $$
begin
  if p_purpose is null or p_purpose not in ('record', 'timeline') then
    raise invalid_parameter_value using message='invalid purpose';
  end if;
  return query
  select el.source_id, pl.fhir_id, el.fhir_id, h.organization_id, h.id, h.patient_id
  from public.hospitalizations h
  join public.fhir_encounter_links el on el.organization_id=h.organization_id and el.hospitalization_id=h.id and el.patient_id=h.patient_id
  join public.fhir_patient_links pl on pl.organization_id=el.organization_id and pl.source_id=el.source_id and pl.patient_id=h.patient_id
  where h.organization_id=p_organization_id and h.id=p_hospitalization_id
    and public.has_active_iam_permission(h.organization_id,'clinical.census.read')
    and public.has_active_iam_permission(h.organization_id,'clinical.patient.read')
    and (p_purpose <> 'timeline' or public.has_active_iam_permission(h.organization_id,'clinical.timeline.read'))
    and private.can_read_clinical_hospitalization(h.organization_id,h.id,case when p_purpose='timeline' then 'clinical.timeline.read' else 'clinical.patient.read' end);
end $$;
