-- FHIR demo census is an opt-in projection; the legacy census remains unchanged.
alter table public.hospitalization_locations
  add constraint hospitalization_locations_episode_row_key
  unique (organization_id, hospitalization_id, id);
alter table public.fhir_encounter_links
  add constraint fhir_encounter_links_episode_key
  unique (organization_id, source_id, fhir_id, hospitalization_id);
create table public.fhir_location_period_links (
  organization_id uuid not null,
  source_id uuid not null,
  encounter_fhir_id text not null,
  location_fhir_id text not null,
  period_key text not null check (btrim(period_key) <> ''),
  hospitalization_id uuid not null,
  location_row_id uuid not null,
  primary key (organization_id, source_id, encounter_fhir_id, location_fhir_id, period_key),
  unique (organization_id, location_row_id),
  foreign key (organization_id, source_id, encounter_fhir_id, hospitalization_id)
    references public.fhir_encounter_links(organization_id, source_id, fhir_id, hospitalization_id) on delete cascade,
  foreign key (organization_id, source_id, location_fhir_id)
    references public.fhir_location_links(organization_id, source_id, fhir_id) on delete cascade,
  foreign key (organization_id, hospitalization_id, location_row_id)
    references public.hospitalization_locations(organization_id, hospitalization_id, id) on delete cascade
);
alter table public.fhir_location_period_links enable row level security;
revoke all on public.fhir_location_period_links from public, anon, authenticated, service_role;

create or replace function private.fhir_census_episode_is_authorized(p_organization_id uuid, p_hospitalization_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null
    and public.has_active_iam_permission(p_organization_id, 'clinical.census.read')
    and public.has_active_iam_permission(p_organization_id, 'clinical.patient.read')
    and private.can_read_clinical_hospitalization(p_organization_id, p_hospitalization_id, 'clinical.patient.read')
    and exists (
      select 1 from public.fhir_encounter_links e
      join public.fhir_patient_links p on p.organization_id=e.organization_id and p.source_id=e.source_id and p.patient_id=e.patient_id
      where e.organization_id=p_organization_id and e.hospitalization_id=p_hospitalization_id
    );
$$;
revoke all on function private.fhir_census_episode_is_authorized(uuid, uuid) from public, anon, authenticated, service_role;
grant execute on function private.fhir_census_episode_is_authorized(uuid, uuid) to authenticated;

create view public.fhir_clinical_census_by_hospitalization
with (security_invoker = true, security_barrier = true) as
select c.* from public.clinical_census_by_hospitalization c
where private.fhir_census_episode_is_authorized(c.organization_id, c.hospitalization_id);
grant select on public.fhir_clinical_census_by_hospitalization to authenticated;
comment on view public.fhir_clinical_census_by_hospitalization is
  'FHIR-linked demo census. Mirrors the legacy census columns while requiring a caller-authorized FHIR encounter/patient mapping.';
comment on table public.fhir_location_period_links is
  'Private ownership manifest for reconstructible FHIR location projections; not an audit history.';
