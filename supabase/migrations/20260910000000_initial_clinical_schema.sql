-- Carer Record initial schema. This file is the sole source of truth for local DB state.
create extension if not exists pgcrypto;

create type public.practitioner_role as enum ('physician', 'nurse', 'technician', 'administrator');
create type public.clinical_event_kind as enum ('observation', 'encounter', 'condition', 'procedure', 'document');

create table public.practitioners (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  role public.practitioner_role not null,
  license_number text unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.patients (
  id uuid primary key default gen_random_uuid(),
  external_reference text unique,
  given_name text not null,
  family_name text not null,
  birth_date date,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint patients_payload_is_object check (jsonb_typeof(payload) = 'object')
);

create table public.clinical_events (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  recorded_by uuid references public.practitioners(id) on delete set null,
  kind public.clinical_event_kind not null,
  occurred_at timestamptz not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint clinical_events_payload_is_object check (jsonb_typeof(payload) = 'object')
);

create index clinical_events_patient_occurred_at_idx on public.clinical_events (patient_id, occurred_at desc);

alter table public.practitioners enable row level security;
alter table public.patients enable row level security;
alter table public.clinical_events enable row level security;

create policy "authenticated users can read practitioners" on public.practitioners for select to authenticated using (true);
create policy "authenticated users can read patients" on public.patients for select to authenticated using (true);
create policy "authenticated users can read clinical events" on public.clinical_events for select to authenticated using (true);

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger practitioners_set_updated_at before update on public.practitioners
for each row execute function public.set_updated_at();
create trigger patients_set_updated_at before update on public.patients
for each row execute function public.set_updated_at();

grant usage on schema public to anon, authenticated;
grant select on public.practitioners, public.patients, public.clinical_events to authenticated;
