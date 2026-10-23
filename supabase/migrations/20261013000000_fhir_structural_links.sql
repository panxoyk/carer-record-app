-- First FHIR structural synchronization contract. No resource payload or source
-- endpoint/credentials are exposed to authenticated clients.
create table public.fhir_sources (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  logical_key text not null check (btrim(logical_key) <> ''),
  created_at timestamptz not null default now(),
  unique (organization_id, id),
  unique (organization_id, logical_key)
);

create table public.fhir_patient_links (
  organization_id uuid not null,
  source_id uuid not null,
  fhir_id text not null check (btrim(fhir_id) <> ''),
  patient_id uuid not null,
  primary key (organization_id, source_id, fhir_id),
  unique (organization_id, source_id, patient_id),
  foreign key (organization_id, source_id) references public.fhir_sources(organization_id, id) on delete restrict,
  foreign key (organization_id, patient_id) references public.patients(organization_id, id) on delete restrict
);
create table public.fhir_encounter_links (
  organization_id uuid not null,
  source_id uuid not null,
  fhir_id text not null check (btrim(fhir_id) <> ''),
  hospitalization_id uuid not null,
  patient_id uuid not null,
  primary key (organization_id, source_id, fhir_id),
  unique (organization_id, source_id, hospitalization_id),
  foreign key (organization_id, source_id) references public.fhir_sources(organization_id, id) on delete restrict,
  foreign key (organization_id, hospitalization_id, patient_id) references public.hospitalizations(organization_id, id, patient_id) on delete restrict,
  foreign key (organization_id, source_id, patient_id) references public.fhir_patient_links(organization_id, source_id, patient_id) on delete restrict
);
create table public.fhir_location_links (
  organization_id uuid not null,
  source_id uuid not null,
  fhir_id text not null check (btrim(fhir_id) <> ''),
  unit_id uuid,
  location_id uuid not null default gen_random_uuid(),
  primary key (organization_id, source_id, fhir_id),
  unique (organization_id, source_id, location_id),
  foreign key (organization_id, source_id) references public.fhir_sources(organization_id, id) on delete restrict,
  foreign key (organization_id, unit_id) references public.units(organization_id, id) on delete restrict
);

alter table public.fhir_sources enable row level security;
alter table public.fhir_patient_links enable row level security;
alter table public.fhir_encounter_links enable row level security;
alter table public.fhir_location_links enable row level security;
revoke all on public.fhir_sources, public.fhir_patient_links, public.fhir_encounter_links, public.fhir_location_links from public, anon, authenticated, service_role;

create or replace function public.fhir_authorized_encounter_context(p_organization_id uuid, p_hospitalization_id uuid, p_purpose text default 'record')
returns table(source_id uuid, patient_fhir_id text, encounter_fhir_id text, organization_id uuid, hospitalization_id uuid, patient_id uuid)
language plpgsql stable security definer set search_path = '' as $$
begin
  if p_purpose not in ('record', 'timeline') then raise invalid_parameter_value using message='invalid purpose'; end if;
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
revoke all on function public.fhir_authorized_encounter_context(uuid,uuid,text) from public, anon, service_role;
grant execute on function public.fhir_authorized_encounter_context(uuid,uuid,text) to authenticated;
comment on function public.fhir_authorized_encounter_context(uuid,uuid,text) is 'Returns one JWT-authorized FHIR mapping context only; never returns source URL or credentials.';

-- Closed episodes remain readable, but cannot accept new context notes.
create or replace function private.can_write_context_note(p_organization_id uuid, p_hospitalization_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
 select public.has_active_iam_permission(p_organization_id,'context.note.create')
 and public.has_active_iam_permission(p_organization_id,'context.note.confirm')
 and private.can_read_clinical_hospitalization(p_organization_id,p_hospitalization_id,'context.note.read')
 and exists(select 1 from public.hospitalizations h where h.organization_id=p_organization_id and h.id=p_hospitalization_id and h.status in ('admitted','temporarily_absent'))
$$;
