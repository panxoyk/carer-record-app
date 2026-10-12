-- Phase 3.2: close the technical-role DML bypass and complete the minimal
-- episode contracts. SECURITY DEFINER bridges owned by the table owner remain
-- able to write; runtime roles cannot write even if grants are added later.
create or replace function private.guard_clinical_runtime_dml()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  table_owner name;
begin
  select pg_catalog.pg_get_userbyid(c.relowner)
    into table_owner
    from pg_catalog.pg_class c
   where c.oid = tg_relid;

  if current_user <> table_owner and not exists (
    select 1 from pg_catalog.pg_roles r where r.rolname = current_user and r.rolsuper
  ) then
    raise insufficient_privilege using
      message = 'clinical data writes are restricted to controlled owner bridges';
  end if;
  return null;
end
$$;
revoke all on function private.guard_clinical_runtime_dml() from public, anon, authenticated, service_role;

create trigger patients_runtime_dml_guard
  before insert or update or delete or truncate on public.patients
  for each statement execute function private.guard_clinical_runtime_dml();
create trigger clinical_events_runtime_dml_guard
  before insert or update or delete or truncate on public.clinical_events
  for each statement execute function private.guard_clinical_runtime_dml();

revoke insert, update, delete, truncate on public.patients, public.clinical_events
  from public, anon, authenticated, service_role;

grant select (id, organization_id, patient_id, hospitalization_id, kind, occurred_at,
  created_at, summary) on public.clinical_events to authenticated;

create or replace view public.clinical_census_by_hospitalization
with (security_invoker = true, security_barrier = true) as
select h.organization_id, h.id as hospitalization_id, h.patient_id,
       h.status as hospitalization_status, h.admitted_at, h.discharged_at,
       location.unit_id, location.bed_label,
       p.given_name, p.family_name, p.birth_date
from public.hospitalizations h
join public.patients p
  on p.organization_id = h.organization_id and p.id = h.patient_id
left join public.hospitalization_locations location
  on location.organization_id = h.organization_id
 and location.hospitalization_id = h.id and location.ended_at is null;

create or replace view public.clinical_timeline_by_hospitalization
with (security_invoker = true, security_barrier = true) as
select e.organization_id, e.hospitalization_id, e.id as event_id,
       e.kind, e.occurred_at, e.summary,
       e.patient_id, e.created_at
from public.clinical_events e;

comment on function private.guard_clinical_runtime_dml() is
  'Rejects runtime DML on clinical source tables unless running as the table owner, a superuser migration, or a controlled owner SECURITY DEFINER bridge.';
comment on view public.clinical_census_by_hospitalization is
  'Episode-scoped census and minimum demographics; demographic rows require both census and patient permissions through base-table RLS.';
comment on view public.clinical_timeline_by_hospitalization is
  'Episode timeline with patient_id and created_at; payload and recorded_by remain private.';
