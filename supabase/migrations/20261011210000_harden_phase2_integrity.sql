-- Phase 2.1 follow-up: close integrity, temporal-overlap, and clinical RLS gaps.

alter table public.hospitalizations
  add constraint hospitalizations_organization_id_id_patient_key
  unique (organization_id, id, patient_id);

alter table public.clinical_events
  add constraint clinical_events_episode_pair_check
  check (
    (organization_id is null and hospitalization_id is null)
    or (organization_id is not null and hospitalization_id is not null)
  );

alter table public.clinical_events drop constraint clinical_events_episode_fk;
alter table public.clinical_events
  add constraint clinical_events_episode_patient_tenant_fk
  foreign key (organization_id, hospitalization_id, patient_id)
  references public.hospitalizations (organization_id, id, patient_id)
  on delete restrict;

alter table public.hospitalization_locations
  add constraint hospitalization_locations_no_overlapping_periods
  exclude using gist (
    organization_id with =,
    hospitalization_id with =,
    tstzrange(started_at, ended_at, '[)') with &&
  );

alter table public.care_assignments
  add constraint care_assignments_no_overlapping_live_assignments
  exclude using gist (
    organization_id with =,
    hospitalization_id with =,
    membership_id with =,
    tstzrange(valid_from, valid_until, '[)') with &&
  ) where (revoked_at is null);

drop policy "authorized members read hospitalizations" on public.hospitalizations;
create policy "authorized members read hospitalizations" on public.hospitalizations for select to authenticated
  using (
    (public.has_active_iam_permission(organization_id, 'clinical.organization.read')
      and public.has_active_iam_permission(organization_id, 'clinical.census.read'))
    or (public.has_active_iam_permission(organization_id, 'clinical.assigned.read')
      and public.has_active_iam_permission(organization_id, 'clinical.census.read')
      and private.has_current_care_assignment(id))
  );

drop policy "authorized members read hospitalization locations" on public.hospitalization_locations;
create policy "authorized members read hospitalization locations" on public.hospitalization_locations for select to authenticated
  using (
    (public.has_active_iam_permission(organization_id, 'clinical.organization.read')
      and public.has_active_iam_permission(organization_id, 'clinical.census.read'))
    or (public.has_active_iam_permission(organization_id, 'clinical.assigned.read')
      and public.has_active_iam_permission(organization_id, 'clinical.census.read')
      and private.has_current_care_assignment(hospitalization_id))
  );
