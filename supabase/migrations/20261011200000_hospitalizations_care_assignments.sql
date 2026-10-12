-- Phase 2.1: tenant-safe hospitalization and care-assignment model.
-- Legacy clinical SELECT policies are intentionally not replaced in this phase.

create table public.units (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  code text not null,
  display_name text not null,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  constraint units_organization_id_id_key unique (organization_id, id),
  constraint units_code_key unique (organization_id, code),
  constraint units_code_not_blank check (length(trim(code)) > 0),
  constraint units_name_not_blank check (length(trim(display_name)) > 0),
  constraint units_status check (status in ('active', 'closed'))
);

alter table public.patients add column organization_id uuid;
alter table public.patients add constraint patients_organization_fk
  foreign key (organization_id) references public.organizations(id) on delete restrict;
alter table public.patients add constraint patients_organization_id_id_key unique (organization_id, id);

create table public.hospitalizations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  patient_id uuid not null,
  status text not null,
  admitted_at timestamptz not null,
  discharged_at timestamptz,
  created_at timestamptz not null default now(),
  constraint hospitalizations_organization_id_id_key unique (organization_id, id),
  constraint hospitalizations_patient_tenant_fk foreign key (organization_id, patient_id)
    references public.patients (organization_id, id) on delete restrict,
  constraint hospitalizations_status check (
    status in ('planned', 'admitted', 'temporarily_absent', 'discharged', 'cancelled', 'entered_in_error')
  ),
  constraint hospitalizations_discharge_order check (
    discharged_at is null or discharged_at >= admitted_at
  ),
  constraint hospitalizations_terminal_time check (
    (status = 'discharged' and discharged_at is not null)
    or (status <> 'discharged' and discharged_at is null)
  )
);
create index hospitalizations_patient_idx on public.hospitalizations (organization_id, patient_id, admitted_at desc);
create index hospitalizations_status_idx on public.hospitalizations (organization_id, status, admitted_at desc);

create table public.hospitalization_locations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  hospitalization_id uuid not null,
  unit_id uuid,
  bed_label text,
  started_at timestamptz not null,
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  constraint hospitalization_locations_organization_id_id_key unique (organization_id, id),
  constraint hospitalization_locations_episode_fk foreign key (organization_id, hospitalization_id)
    references public.hospitalizations (organization_id, id) on delete restrict,
  constraint hospitalization_locations_unit_fk foreign key (organization_id, unit_id)
    references public.units (organization_id, id) on delete restrict,
  constraint hospitalization_locations_interval check (ended_at is null or ended_at > started_at),
  constraint hospitalization_locations_bed_not_blank check (bed_label is null or length(trim(bed_label)) > 0)
);
create index hospitalization_locations_episode_idx on public.hospitalization_locations (organization_id, hospitalization_id, started_at desc);
create unique index hospitalization_locations_one_current_idx on public.hospitalization_locations (organization_id, hospitalization_id) where ended_at is null;

create table public.care_assignments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  hospitalization_id uuid not null,
  membership_id uuid not null,
  relationship_code text,
  valid_from timestamptz not null,
  valid_until timestamptz,
  revoked_at timestamptz,
  revoked_by_membership_id uuid,
  created_by_membership_id uuid not null,
  created_at timestamptz not null default now(),
  constraint care_assignments_organization_id_id_key unique (organization_id, id),
  constraint care_assignments_episode_fk foreign key (organization_id, hospitalization_id)
    references public.hospitalizations (organization_id, id) on delete restrict,
  constraint care_assignments_membership_fk foreign key (organization_id, membership_id)
    references public.organization_memberships (organization_id, id) on delete restrict,
  constraint care_assignments_creator_fk foreign key (organization_id, created_by_membership_id)
    references public.organization_memberships (organization_id, id) on delete restrict,
  constraint care_assignments_revoker_fk foreign key (organization_id, revoked_by_membership_id)
    references public.organization_memberships (organization_id, id) on delete restrict,
  constraint care_assignments_interval check (valid_until is null or valid_until > valid_from),
  constraint care_assignments_revocation_order check (revoked_at is null or revoked_at >= created_at),
  constraint care_assignments_relationship_not_blank check (relationship_code is null or length(trim(relationship_code)) > 0)
);
create index care_assignments_membership_validity_idx on public.care_assignments (organization_id, membership_id, valid_from, valid_until) where revoked_at is null;
create index care_assignments_episode_idx on public.care_assignments (organization_id, hospitalization_id, membership_id);
create unique index care_assignments_no_duplicate_live_grant_idx on public.care_assignments
  (organization_id, hospitalization_id, membership_id) where revoked_at is null and valid_until is null;

alter table public.clinical_events
  add column organization_id uuid,
  add column hospitalization_id uuid;
alter table public.clinical_events add constraint clinical_events_episode_fk
  foreign key (organization_id, hospitalization_id)
  references public.hospitalizations (organization_id, id) on delete restrict;
create index clinical_events_episode_timeline_idx
  on public.clinical_events (organization_id, hospitalization_id, occurred_at desc)
  where hospitalization_id is not null;

create index units_organization_status_idx on public.units (organization_id, status, display_name);

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create or replace function private.has_current_care_assignment(p_hospitalization_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.hospitalizations h
    join public.care_assignments ca
      on ca.organization_id = h.organization_id and ca.hospitalization_id = h.id
    join public.organization_memberships m
      on m.organization_id = ca.organization_id and m.id = ca.membership_id
    join public.profiles p on p.id = m.profile_id
    join public.organizations o on o.id = h.organization_id
    where h.id = p_hospitalization_id
      and h.status not in ('cancelled', 'entered_in_error')
      and p.auth_user_id = auth.uid() and p.status = 'active'
      and m.status = 'active' and m.valid_from <= now()
      and (m.valid_until is null or m.valid_until > now())
      and o.status = 'active'
      and ca.revoked_at is null and ca.valid_from <= now()
      and (ca.valid_until is null or ca.valid_until > now())
  )
$$;

alter table public.units enable row level security;
alter table public.hospitalizations enable row level security;
alter table public.hospitalization_locations enable row level security;
alter table public.care_assignments enable row level security;

create policy "active members read units" on public.units for select to authenticated
  using (public.has_active_organization_membership(organization_id));
create policy "authorized members read hospitalizations" on public.hospitalizations for select to authenticated
  using (
    (public.has_active_iam_permission(organization_id, 'clinical.assignment.manage')
      and public.has_active_iam_permission(organization_id, 'clinical.census.read'))
    or (public.has_active_iam_permission(organization_id, 'clinical.assigned.read')
      and public.has_active_iam_permission(organization_id, 'clinical.census.read')
      and private.has_current_care_assignment(id))
  );
create policy "authorized members read hospitalization locations" on public.hospitalization_locations for select to authenticated
  using (
    (public.has_active_iam_permission(organization_id, 'clinical.assignment.manage')
      and public.has_active_iam_permission(organization_id, 'clinical.census.read'))
    or (public.has_active_iam_permission(organization_id, 'clinical.assigned.read')
      and public.has_active_iam_permission(organization_id, 'clinical.census.read')
      and private.has_current_care_assignment(hospitalization_id))
  );
create policy "members read own or managed care assignments" on public.care_assignments for select to authenticated
  using (
    public.is_current_active_membership(membership_id)
    or public.has_active_iam_permission(organization_id, 'clinical.assignment.manage')
  );

revoke all on public.units, public.hospitalizations, public.hospitalization_locations, public.care_assignments from public, anon, authenticated;
grant select on public.units, public.hospitalizations, public.hospitalization_locations, public.care_assignments to authenticated;
revoke all on function private.has_current_care_assignment(uuid) from public, anon;
grant execute on function private.has_current_care_assignment(uuid) to authenticated;

-- Versioned deterministic fixture bridge. It only maps the explicit seed UUIDs below;
-- no production/runtime inference from care_unit, bed_label, recorded_by, or authorship.
create or replace function public.bootstrap_synthetic_hospitalization_fixtures()
returns void language plpgsql security definer set search_path = '' as $$
declare
  org uuid;
  unit_medicine uuid;
  unit_surgery uuid;
  unit_icu uuid;
  unit_pediatrics uuid;
  unit_emergency uuid;
  unit_intermediate uuid;
  ana_membership uuid;
  matias_membership uuid;
  admin_membership uuid;
begin
  select id into strict org from public.organizations where slug = 'demo-hospital';
  insert into public.units (organization_id, code, display_name) values
    (org, 'medicine', 'Medicina interna'), (org, 'surgery', 'Cirugía'),
    (org, 'adult-icu', 'UCI adulto'), (org, 'pediatrics', 'Pediatría'),
    (org, 'emergency', 'Urgencia'), (org, 'intermediate-care', 'Unidad de Cuidados Intermedios')
  on conflict (organization_id, code) do nothing;
  select id into strict unit_medicine from public.units where organization_id=org and code='medicine';
  select id into strict unit_surgery from public.units where organization_id=org and code='surgery';
  select id into strict unit_icu from public.units where organization_id=org and code='adult-icu';
  select id into strict unit_pediatrics from public.units where organization_id=org and code='pediatrics';
  select id into strict unit_emergency from public.units where organization_id=org and code='emergency';
  select id into strict unit_intermediate from public.units where organization_id=org and code='intermediate-care';
  update public.patients set organization_id=org where id in (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    '70000000-0000-0000-0000-000000000003','70000000-0000-0000-0000-000000000004',
    '70000000-0000-0000-0000-000000000005','70000000-0000-0000-0000-000000000006',
    '70000000-0000-0000-0000-000000000007','70000000-0000-0000-0000-000000000008'
  );
  insert into public.hospitalizations (id, organization_id, patient_id, status, admitted_at, discharged_at)
  select f.id, org, f.patient_id, f.status, now() - f.admitted_ago, case when f.status='discharged' then now()-interval '1 day' else null end
  from (values
    ('a1000000-0000-0000-0000-000000000001'::uuid,'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,'admitted'::text,interval '7 days'),
    ('a1000000-0000-0000-0000-000000000002','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','discharged',interval '40 days'),
    ('a1000000-0000-0000-0000-000000000003','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','admitted',interval '5 days'),
    ('a1000000-0000-0000-0000-000000000004','70000000-0000-0000-0000-000000000003','admitted',interval '8 days'),
    ('a1000000-0000-0000-0000-000000000005','70000000-0000-0000-0000-000000000004','admitted',interval '3 days'),
    ('a1000000-0000-0000-0000-000000000006','70000000-0000-0000-0000-000000000005','admitted',interval '4 days'),
    ('a1000000-0000-0000-0000-000000000007','70000000-0000-0000-0000-000000000006','admitted',interval '20 days'),
    ('a1000000-0000-0000-0000-000000000008','70000000-0000-0000-0000-000000000007','admitted',interval '1 day'),
    ('a1000000-0000-0000-0000-000000000009','70000000-0000-0000-0000-000000000008','admitted',interval '8 days')
  ) f(id,patient_id,status,admitted_ago)
  join public.patients p on p.id=f.patient_id and p.organization_id=org
  on conflict (id) do nothing;
  insert into public.hospitalization_locations (organization_id,hospitalization_id,unit_id,bed_label,started_at)
  select org, f.hid, f.unit_id, f.bed, h.admitted_at from (values
    ('a1000000-0000-0000-0000-000000000001'::uuid,unit_medicine,'Cama 12'::text),
    ('a1000000-0000-0000-0000-000000000002',unit_medicine,'Cama 12'),
    ('a1000000-0000-0000-0000-000000000003',unit_surgery,'Cama 07'),
    ('a1000000-0000-0000-0000-000000000004',unit_icu,'Cama 03'),
    ('a1000000-0000-0000-0000-000000000005',unit_pediatrics,'Cuna 04'),
    ('a1000000-0000-0000-0000-000000000006',unit_emergency,'Box 06'),
    ('a1000000-0000-0000-0000-000000000007',unit_intermediate,'Cama 21'),
    ('a1000000-0000-0000-0000-000000000009',unit_medicine,'Cama 14')
  ) f(hid,unit_id,bed) join public.hospitalizations h on h.id=f.hid and h.organization_id=org
  where not exists (
    select 1 from public.hospitalization_locations existing
    where existing.organization_id=org and existing.hospitalization_id=f.hid
  )
  on conflict (id) do nothing;
  update public.hospitalization_locations l set ended_at=h.discharged_at
  from public.hospitalizations h where l.hospitalization_id=h.id and h.status='discharged' and l.ended_at is null;
  update public.clinical_events e set organization_id=org, hospitalization_id=f.hid
  from (values
    ('cccccccc-cccc-cccc-cccc-cccccccccccc'::uuid,'a1000000-0000-0000-0000-000000000001'::uuid),
    ('dddddddd-dddd-dddd-dddd-dddddddddddd','a1000000-0000-0000-0000-000000000001'),
    ('80000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000002'),
    ('80000000-0000-0000-0000-000000000002','a1000000-0000-0000-0000-000000000002'),
    ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee','a1000000-0000-0000-0000-000000000003'),
    ('80000000-0000-0000-0000-000000000003','a1000000-0000-0000-0000-000000000003'),
    ('80000000-0000-0000-0000-000000000004','a1000000-0000-0000-0000-000000000003'),
    ('80000000-0000-0000-0000-000000000005','a1000000-0000-0000-0000-000000000004'),
    ('80000000-0000-0000-0000-000000000006','a1000000-0000-0000-0000-000000000004'),
    ('80000000-0000-0000-0000-000000000007','a1000000-0000-0000-0000-000000000004'),
    ('80000000-0000-0000-0000-000000000008','a1000000-0000-0000-0000-000000000004'),
    ('80000000-0000-0000-0000-000000000009','a1000000-0000-0000-0000-000000000005'),
    ('80000000-0000-0000-0000-000000000010','a1000000-0000-0000-0000-000000000005'),
    ('80000000-0000-0000-0000-000000000011','a1000000-0000-0000-0000-000000000006'),
    ('80000000-0000-0000-0000-000000000012','a1000000-0000-0000-0000-000000000006'),
    ('80000000-0000-0000-0000-000000000013','a1000000-0000-0000-0000-000000000007'),
    ('80000000-0000-0000-0000-000000000014','a1000000-0000-0000-0000-000000000007'),
    ('80000000-0000-0000-0000-000000000015','a1000000-0000-0000-0000-000000000008')
  ) f(event_id,hid) join public.hospitalizations h on h.id=f.hid and h.organization_id=org
  where e.id=f.event_id and e.patient_id=h.patient_id;
  select m.id into ana_membership from public.organization_memberships m join public.profiles p on p.id=m.profile_id where m.organization_id=org and p.auth_user_id='11111111-1111-1111-1111-111111111111';
  select m.id into matias_membership from public.organization_memberships m join public.profiles p on p.id=m.profile_id where m.organization_id=org and p.auth_user_id='22222222-2222-2222-2222-222222222222';
  select m.id into admin_membership from public.organization_memberships m join public.profiles p on p.id=m.profile_id where m.organization_id=org and p.auth_user_id='33333333-3333-3333-3333-333333333333';
  insert into public.care_assignments (organization_id,hospitalization_id,membership_id,valid_from,created_by_membership_id)
  select org, x.hid, x.membership_id, now()-interval '90 days', admin_membership from (values
    ('a1000000-0000-0000-0000-000000000001'::uuid,ana_membership),
    ('a1000000-0000-0000-0000-000000000002',ana_membership),
    ('a1000000-0000-0000-0000-000000000003',matias_membership),
    ('a1000000-0000-0000-0000-000000000004',ana_membership),
    ('a1000000-0000-0000-0000-000000000005',matias_membership),
    ('a1000000-0000-0000-0000-000000000006',ana_membership),
    ('a1000000-0000-0000-0000-000000000007',matias_membership),
    ('a1000000-0000-0000-0000-000000000008',ana_membership),
    ('a1000000-0000-0000-0000-000000000008',matias_membership)
  ) x(hid,membership_id)
  join public.hospitalizations h on h.id=x.hid and h.organization_id=org
  where x.membership_id is not null
  on conflict do nothing;
end
$$;
revoke all on function public.bootstrap_synthetic_hospitalization_fixtures() from public, anon, authenticated;
comment on function public.bootstrap_synthetic_hospitalization_fixtures() is
  'Migration/seed-only explicit synthetic fixture bridge; no runtime clinical inference.';
select public.bootstrap_synthetic_hospitalization_fixtures();
