-- ADR-022: event categories chosen by the author, author profession snapshot,
-- service (unit) name in the census and a bounded write context for clinical
-- photos stored in the FHIR server. Additive only; RLS remains the authority.

-- 1. Profession of an organization member (clinical estamento). Nullable: an
--    administrative member may have none. Managed by IAM operations, never by
--    the note author.
alter table public.organization_memberships
  add column profession text
  constraint organization_memberships_profession_check
  check (profession is null or profession in
    ('medicina', 'enfermeria', 'tens', 'kinesiologia', 'nutricion', 'otro'));

comment on column public.organization_memberships.profession is
  'Clinical profession of the member (ADR-022). Snapshotted into context notes for timeline filters.';

-- 2. Category chosen by the professional for each context note, plus the
--    profession of the author captured at insert time for audit and filters.
alter table public.context_notes
  add column category text not null default 'nota_clinica'
  constraint context_notes_category_check
  check (category in ('rutina', 'movilidad', 'nota_clinica', 'farmacologia',
    'procedimiento', 'signos_vitales', 'tens', 'nutricion', 'comunicacion')),
  add column author_profession text
  constraint context_notes_author_profession_check
  check (author_profession is null or author_profession in
    ('medicina', 'enfermeria', 'tens', 'kinesiologia', 'nutricion', 'otro'));

create or replace function private.snapshot_context_note_author_profession()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- Never trust a client value: the profession comes from the author's active
  -- membership in the note organization.
  select m.profession into new.author_profession
    from public.organization_memberships m
    join public.profiles p on p.id = m.profile_id
   where p.auth_user_id = auth.uid()
     and m.organization_id = new.organization_id
     and m.status = 'active'
     and m.valid_from <= now()
     and (m.valid_until is null or m.valid_until > now())
   limit 1;
  return new;
end $$;
revoke all on function private.snapshot_context_note_author_profession()
  from public, anon, authenticated, service_role;

create trigger context_notes_author_profession_snapshot
before insert on public.context_notes
for each row execute function private.snapshot_context_note_author_profession();

revoke all on public.context_notes from public, anon, authenticated, service_role;
grant select (id, organization_id, hospitalization_id, patient_id, input_method,
  content, transcription_metadata, status, occurred_at, created_at, category,
  author_profession, client_event_id)
  on public.context_notes to authenticated;
grant insert (organization_id, hospitalization_id, patient_id, input_method,
  content, transcription_metadata, client_event_id, category)
  on public.context_notes to authenticated;

-- Reconciliation also compares the category so a retry never confirms a note
-- that differs from the one the author published.
create or replace function public.context_note_publication_matches(
  p_organization_id uuid, p_hospitalization_id uuid, p_patient_id uuid,
  p_input_method text, p_content text, p_transcription_metadata jsonb,
  p_client_event_id uuid, p_category text
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
      and n.category = p_category
      and n.author_id = auth.uid() and n.status = 'confirmed'
  );
end $$;
revoke all on function public.context_note_publication_matches(
  uuid, uuid, uuid, text, text, jsonb, uuid, text) from public, anon;
grant execute on function public.context_note_publication_matches(
  uuid, uuid, uuid, text, text, jsonb, uuid, text) to authenticated;

-- 3. Timeline exposes the category and author profession of notes. Clinical
--    events keep null for both.
create or replace view public.clinical_timeline_by_hospitalization
with (security_invoker = true, security_barrier = true) as
select e.organization_id, e.hospitalization_id, e.id as event_id,
       e.kind::text, e.occurred_at, e.summary,
       e.patient_id, e.created_at,
       'clinical_event'::text as source_kind,
       null::text as author_display_name,
       null::text as category,
       null::text as author_profession,
       null::uuid as client_event_id
from public.clinical_events e
union all
select n.organization_id, n.hospitalization_id, n.id,
       case when n.input_method = 'audio' then 'milestone_audio' else 'milestone' end,
       n.occurred_at,
       n.content,
       n.patient_id, n.created_at,
       'context_note'::text,
       private.context_note_timeline_author_name(n.id, n.organization_id, n.hospitalization_id),
       n.category,
       n.author_profession,
       n.client_event_id
from public.context_notes n
where n.status = 'confirmed';

revoke all on public.clinical_timeline_by_hospitalization from public, anon;
grant select on public.clinical_timeline_by_hospitalization to authenticated;
comment on view public.clinical_timeline_by_hospitalization is
  'Episode timeline of clinical events and confirmed context milestones with author-chosen category, author profession snapshot and the note client event id that links clinical photos (ADR-022). Author UUID and email remain private.';

-- 4. Service name in the census without granting org.unit.read: resolved only
--    for an episode the caller can already read.
create or replace function private.census_unit_display_name(
  p_organization_id uuid, p_hospitalization_id uuid, p_unit_id uuid
)
returns text language sql stable security definer set search_path = '' as $$
  select u.display_name
    from public.units u
   where u.organization_id = p_organization_id
     and u.id = p_unit_id
     and private.can_read_clinical_hospitalization(
       p_organization_id, p_hospitalization_id, 'clinical.census.read')
$$;
revoke all on function private.census_unit_display_name(uuid, uuid, uuid)
  from public, anon, service_role;
grant execute on function private.census_unit_display_name(uuid, uuid, uuid)
  to authenticated;

create or replace view public.clinical_census_by_hospitalization
with (security_invoker = true, security_barrier = true) as
select h.organization_id, h.id as hospitalization_id, h.patient_id,
       h.status as hospitalization_status, h.admitted_at, h.discharged_at,
       location.unit_id, location.bed_label,
       p.given_name, p.family_name, p.birth_date,
       private.census_unit_display_name(h.organization_id, h.id, location.unit_id)
         as unit_display_name
from public.hospitalizations h
join public.patients p
  on p.organization_id = h.organization_id and p.id = h.patient_id
left join public.hospitalization_locations location
  on location.organization_id = h.organization_id
 and location.hospitalization_id = h.id and location.ended_at is null;

create or replace view public.fhir_clinical_census_by_hospitalization
with (security_invoker = true, security_barrier = true) as
select c.organization_id, c.hospitalization_id, c.patient_id,
       c.hospitalization_status, c.admitted_at, c.discharged_at,
       c.unit_id, c.bed_label, c.given_name, c.family_name, c.birth_date,
       c.unit_display_name
from public.clinical_census_by_hospitalization c
where private.fhir_census_episode_is_authorized(c.organization_id, c.hospitalization_id);

comment on view public.clinical_census_by_hospitalization is
  'Episode-scoped census and minimum demographics; unit_display_name is resolved only for readable episodes (ADR-022).';

-- 5. Current member context exposes profession and institutional identifier.
create or replace view public.iam_current_context
with (security_invoker = true, security_barrier = true)
as
select o.id as organization_id, o.display_name as organization_name,
       p.id as profile_id, p.display_name, p.status as profile_status,
       m.id as membership_id, m.status as membership_status,
       permission.code as permission_code,
       m.profession,
       m.local_identifier
from public.profiles p
join public.organization_memberships m on m.profile_id = p.id
join public.organizations o on o.id = m.organization_id
left join lateral (
  select pc.code
  from public.permission_catalog pc
  where pc.status = 'active'
    and public.has_active_iam_permission(m.organization_id, pc.code)
) permission on true
where p.id = public.iam_current_profile_id()
  and p.status = 'active'
  and m.status = 'active'
  and m.valid_from <= now()
  and (m.valid_until is null or m.valid_until > now())
  and o.status = 'active';

-- 6. Bounded write context for clinical photos (DocumentReference in FHIR).
insert into public.permission_catalog(code, family, description, delegation_policy)
values ('clinical.document.create', 'clinical',
  'Attach clinical photos to an open, accessible episode through the FHIR gateway.',
  'ordinary')
on conflict (code) do nothing;

insert into public.role_permissions(organization_id, role_id, permission_code)
select r.organization_id, r.id, 'clinical.document.create'
from public.roles r join public.organizations o on o.id = r.organization_id
where o.slug = 'demo-hospital'
  and (r.protected_kind = 'demo_administrator' or exists (
    select 1 from public.role_permissions rp
    where rp.organization_id = r.organization_id and rp.role_id = r.id
      and rp.permission_code = 'clinical.timeline.read'
  ))
on conflict do nothing;

create or replace function public.fhir_authorized_encounter_write_context(
  p_organization_id uuid, p_hospitalization_id uuid
)
returns table(source_id uuid, patient_fhir_id text, encounter_fhir_id text,
  organization_id uuid, hospitalization_id uuid, patient_id uuid)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.has_active_iam_permission(p_organization_id, 'clinical.document.create')
    or not private.can_write_context_note(p_organization_id, p_hospitalization_id)
  then
    return;
  end if;
  return query
  select el.source_id, pl.fhir_id, el.fhir_id, h.organization_id, h.id, h.patient_id
  from public.hospitalizations h
  join public.fhir_encounter_links el
    on el.organization_id = h.organization_id and el.hospitalization_id = h.id
   and el.patient_id = h.patient_id
  join public.fhir_patient_links pl
    on pl.organization_id = el.organization_id and pl.source_id = el.source_id
   and pl.patient_id = h.patient_id
  where h.organization_id = p_organization_id and h.id = p_hospitalization_id
    and h.status in ('admitted', 'temporarily_absent');
end $$;
revoke all on function public.fhir_authorized_encounter_write_context(uuid, uuid)
  from public, anon, service_role;
grant execute on function public.fhir_authorized_encounter_write_context(uuid, uuid)
  to authenticated;
comment on function public.fhir_authorized_encounter_write_context(uuid, uuid) is
  'Returns FHIR identifiers of an open episode only when the caller may publish notes and attach clinical photos (ADR-022). Empty otherwise.';
