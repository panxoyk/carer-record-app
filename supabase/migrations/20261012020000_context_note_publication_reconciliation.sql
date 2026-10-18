create or replace function public.context_note_publication_matches(
  p_organization_id uuid,
  p_hospitalization_id uuid,
  p_patient_id uuid,
  p_input_method text,
  p_content text,
  p_transcription_metadata jsonb,
  p_client_event_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null
    or not private.can_write_context_note(p_organization_id, p_hospitalization_id)
  then
    raise insufficient_privilege using message = 'permission denied';
  end if;

  return exists (
    select 1
    from public.context_notes n
    where n.organization_id = p_organization_id
      and n.hospitalization_id = p_hospitalization_id
      and n.patient_id = p_patient_id
      and n.input_method = p_input_method
      and n.content = pg_catalog.btrim(p_content)
      and n.transcription_metadata is not distinct from p_transcription_metadata
      and n.client_event_id = p_client_event_id
      and n.author_id = auth.uid()
      and n.status = 'confirmed'
  );
end;
$$;

comment on function public.context_note_publication_matches(uuid, uuid, uuid, text, text, jsonb, uuid) is
  'Read-only reconciliation for an ambiguous context-note INSERT; reauthorizes before returning whether the caller authored an exact confirmed payload match.';

revoke all on function public.context_note_publication_matches(uuid, uuid, uuid, text, text, jsonb, uuid)
  from public, anon, service_role;
grant execute on function public.context_note_publication_matches(uuid, uuid, uuid, text, text, jsonb, uuid)
  to authenticated;
