-- Active patient location is independent from a clinical encounter.
alter table public.patients
  add column rut text,
  add column care_unit text,
  add column bed_label text;

create or replace function public.normalize_rut(value text)
returns text
language sql
immutable
set search_path = public
as $$
  select upper(regexp_replace(trim(value), '[.[:space:]]', '', 'g'));
$$;

create or replace function public.normalize_patient_rut()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.rut is not null then
    new.rut = public.normalize_rut(new.rut);
  end if;
  return new;
end;
$$;

create trigger patients_normalize_rut
before insert or update of rut on public.patients
for each row execute function public.normalize_patient_rut();

alter table public.patients
  add constraint patients_rut_format
    check (rut is null or rut ~ '^[0-9]{7,8}-[0-9K]$'),
  add constraint patients_care_unit_not_blank
    check (care_unit is null or length(trim(care_unit)) > 0),
  add constraint patients_bed_label_not_blank
    check (bed_label is null or length(trim(bed_label)) > 0);

create unique index patients_rut_unique_idx on public.patients (rut)
where rut is not null;
create index patients_care_location_idx on public.patients (care_unit, bed_label);

alter table public.clinical_events
  add constraint clinical_events_payload_has_summary
    check (
      payload ? 'summary'
      and jsonb_typeof(payload -> 'summary') = 'string'
      and length(trim(payload ->> 'summary')) > 0
    );

-- Event timelines follow the same read-only clinical permission matrix as patients.
create or replace function public.can_read_clinical_events()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_read_patients();
$$;

grant execute on function public.can_read_clinical_events() to authenticated;
grant select on public.clinical_events to authenticated;

create policy "active care roles read clinical events" on public.clinical_events
  for select to authenticated using (public.can_read_clinical_events());
