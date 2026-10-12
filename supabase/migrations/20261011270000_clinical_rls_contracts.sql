-- Phase 3: replace legacy clinical reads atomically and expose episode-scoped
-- contracts. The existing Flutter repositories remain temporarily incompatible.
create or replace function private.can_read_clinical_hospitalization(
  p_organization_id uuid,
  p_hospitalization_id uuid,
  p_permission_code text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.hospitalizations h
    join public.organizations o on o.id = h.organization_id
    where h.organization_id = p_organization_id
      and h.id = p_hospitalization_id
      and o.status = 'active'
      and h.status not in ('cancelled', 'entered_in_error')
      and (
        (public.has_active_iam_permission(h.organization_id, 'clinical.organization.read')
          and public.has_active_iam_permission(h.organization_id, p_permission_code))
        or
        (public.has_active_iam_permission(h.organization_id, 'clinical.assigned.read')
          and public.has_active_iam_permission(h.organization_id, p_permission_code)
          and private.has_current_care_assignment(h.id))
      )
  )
$$;
revoke all on function private.can_read_clinical_hospitalization(uuid, uuid, text) from public, anon;
grant execute on function private.can_read_clinical_hospitalization(uuid, uuid, text) to authenticated;

drop policy "active care roles read patients" on public.patients;
drop policy "active care roles read clinical events" on public.clinical_events;
drop function public.can_read_clinical_events();
drop function public.can_read_patients();

create policy "authorized patients by accessible hospitalization" on public.patients
  for select to authenticated using (
    organization_id is not null and exists (
      select 1 from public.hospitalizations h
      where h.organization_id = patients.organization_id
        and h.patient_id = patients.id
        and private.can_read_clinical_hospitalization(
          h.organization_id, h.id, 'clinical.patient.read'
        )
    )
  );

create policy "authorized events by exact hospitalization" on public.clinical_events
  for select to authenticated using (
    organization_id is not null and hospitalization_id is not null
    and private.can_read_clinical_hospitalization(
      organization_id, hospitalization_id, 'clinical.timeline.read'
    )
  );

drop policy "authorized members read hospitalizations" on public.hospitalizations;
create policy "authorized members read hospitalizations" on public.hospitalizations
  for select to authenticated using (
    private.can_read_clinical_hospitalization(
      organization_id, id, 'clinical.census.read'
    )
  );
drop policy "authorized members read hospitalization locations" on public.hospitalization_locations;
create policy "authorized members read hospitalization locations" on public.hospitalization_locations
  for select to authenticated using (
    private.can_read_clinical_hospitalization(
      organization_id, hospitalization_id, 'clinical.census.read'
    )
  );

alter table public.clinical_events add column summary text;
update public.clinical_events set summary = payload ->> 'summary';
alter table public.clinical_events add constraint clinical_events_summary_matches_payload
  check (summary is not distinct from (payload ->> 'summary'));
alter table public.clinical_events alter column summary set not null;

create or replace function private.sync_clinical_event_summary()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.summary := new.payload ->> 'summary';
  return new;
end
$$;
create trigger clinical_events_sync_summary
  before insert or update of payload on public.clinical_events
  for each row execute function private.sync_clinical_event_summary();
revoke all on function private.sync_clinical_event_summary() from public, anon, authenticated;

revoke all on public.patients, public.clinical_events from public, anon, authenticated;
grant select (id, organization_id, given_name, family_name, birth_date)
  on public.patients to authenticated;
grant select (id, organization_id, hospitalization_id, kind, occurred_at, summary)
  on public.clinical_events to authenticated;
grant select (id, organization_id, patient_id, status, admitted_at, discharged_at)
  on public.hospitalizations to authenticated;
grant select (organization_id, hospitalization_id, unit_id, bed_label, started_at, ended_at)
  on public.hospitalization_locations to authenticated;
revoke select on public.hospitalizations, public.hospitalization_locations from authenticated;
grant select (id, organization_id, patient_id, status, admitted_at, discharged_at)
  on public.hospitalizations to authenticated;
grant select (organization_id, hospitalization_id, unit_id, bed_label, started_at, ended_at)
  on public.hospitalization_locations to authenticated;

create view public.clinical_census_by_hospitalization
with (security_invoker = true, security_barrier = true) as
select h.organization_id, h.id as hospitalization_id, h.patient_id,
       h.status as hospitalization_status, h.admitted_at, h.discharged_at,
       location.unit_id, location.bed_label
from public.hospitalizations h
left join public.hospitalization_locations location
  on location.organization_id = h.organization_id
 and location.hospitalization_id = h.id and location.ended_at is null;

create view public.clinical_patient_demographics_by_hospitalization
with (security_invoker = true, security_barrier = true) as
select h.organization_id, h.id as hospitalization_id, p.id as patient_id,
       p.given_name, p.family_name, p.birth_date
from public.hospitalizations h
join public.patients p on p.organization_id = h.organization_id and p.id = h.patient_id;

create view public.clinical_timeline_by_hospitalization
with (security_invoker = true, security_barrier = true) as
select e.organization_id, e.hospitalization_id, e.id as event_id,
       e.kind, e.occurred_at, e.summary
from public.clinical_events e;

revoke all on public.clinical_census_by_hospitalization,
  public.clinical_patient_demographics_by_hospitalization,
  public.clinical_timeline_by_hospitalization from public, anon;
grant select on public.clinical_census_by_hospitalization,
  public.clinical_patient_demographics_by_hospitalization,
  public.clinical_timeline_by_hospitalization to authenticated;

comment on function private.can_read_clinical_hospitalization(uuid, uuid, text) is
  'Requires active tenant, exact non-cancelled hospitalization, concrete permission and either reserved organization-read or current exact care assignment.';
comment on view public.clinical_census_by_hospitalization is
  'Minimal episode-scoped census; invoker grants and base-table RLS apply.';
comment on view public.clinical_patient_demographics_by_hospitalization is
  'Minimum demographics scoped to an accessible hospitalization; no identifiers.';
comment on view public.clinical_timeline_by_hospitalization is
  'Typed episode timeline; JSONB payload and provenance are not exposed.';
