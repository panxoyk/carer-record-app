-- Phase 1 IAM foundation. Clinical legacy policies intentionally remain unchanged.

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  slug text not null,
  display_name text not null,
  status text not null default 'active',
  timezone text not null default 'America/Santiago',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint organizations_slug_not_blank check (length(trim(slug)) > 0),
  constraint organizations_slug_normalized check (slug = lower(trim(slug))),
  constraint organizations_display_name_not_blank check (length(trim(display_name)) > 0),
  constraint organizations_status check (status in ('active', 'suspended', 'closed')),
  constraint organizations_timezone_not_blank check (length(trim(timezone)) > 0),
  constraint organizations_slug_key unique (slug)
);

create table public.profiles (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users(id) on delete restrict,
  display_name text not null,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_auth_user_id_key unique (auth_user_id),
  constraint profiles_display_name_not_blank check (length(trim(display_name)) > 0),
  constraint profiles_status check (status in ('active', 'suspended'))
);

create table public.organization_memberships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  profile_id uuid not null references public.profiles(id) on delete restrict,
  local_identifier text,
  status text not null default 'active',
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint organization_memberships_organization_id_id_key unique (organization_id, id),
  constraint organization_memberships_organization_profile_key unique (organization_id, profile_id),
  constraint organization_memberships_status check (status in ('invited', 'active', 'suspended', 'ended')),
  constraint organization_memberships_local_identifier_not_blank check (
    local_identifier is null or length(trim(local_identifier)) > 0
  ),
  constraint organization_memberships_validity check (
    valid_until is null or valid_until > valid_from
  )
);

create unique index organization_memberships_local_identifier_key
  on public.organization_memberships (organization_id, local_identifier)
  where local_identifier is not null;
create index organization_memberships_profile_status_idx
  on public.organization_memberships (profile_id, status);
create index organization_memberships_organization_status_idx
  on public.organization_memberships (organization_id, status);

create table public.permission_catalog (
  code text primary key,
  family text not null,
  description text not null,
  status text not null default 'active',
  delegation_policy text not null default 'ordinary',
  introduced_at timestamptz not null default now(),
  deprecated_at timestamptz,
  constraint permission_catalog_code_format check (code ~ '^[a-z]+(\.[a-z_]+)+$'),
  constraint permission_catalog_family_not_blank check (length(trim(family)) > 0),
  constraint permission_catalog_description_not_blank check (length(trim(description)) > 0),
  constraint permission_catalog_status check (status in ('active', 'deprecated')),
  constraint permission_catalog_delegation_policy check (
    delegation_policy in ('ordinary', 'system_only')
  ),
  constraint permission_catalog_deprecation check (
    (status = 'active' and deprecated_at is null)
    or (status = 'deprecated' and deprecated_at is not null)
  )
);

create index permission_catalog_family_status_idx
  on public.permission_catalog (family, status);

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  name text not null,
  description text not null,
  status text not null default 'active',
  is_system boolean not null default false,
  protected_kind text,
  created_by_membership_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint roles_organization_id_id_key unique (organization_id, id),
  constraint roles_name_not_blank check (length(trim(name)) > 0),
  constraint roles_description_not_blank check (length(trim(description)) > 0),
  constraint roles_status check (status in ('active', 'inactive')),
  constraint roles_protected_kind check (
    protected_kind is null or protected_kind = 'demo_administrator'
  ),
  constraint roles_protected_kind_is_system check (
    protected_kind is null or is_system
  ),
  constraint roles_created_by_membership_tenant_fk foreign key (
    organization_id, created_by_membership_id
  ) references public.organization_memberships (organization_id, id) on delete restrict
);

create unique index roles_organization_name_ci_key
  on public.roles (organization_id, lower(name));
create unique index roles_one_demo_administrator_key
  on public.roles (organization_id)
  where protected_kind = 'demo_administrator';
create index roles_organization_status_idx
  on public.roles (organization_id, status);

create table public.role_permissions (
  organization_id uuid not null,
  role_id uuid not null,
  permission_code text not null references public.permission_catalog(code) on delete restrict,
  granted_at timestamptz not null default now(),
  granted_by_membership_id uuid,
  primary key (role_id, permission_code),
  constraint role_permissions_organization_role_key unique (organization_id, role_id, permission_code),
  constraint role_permissions_role_tenant_fk foreign key (organization_id, role_id)
    references public.roles (organization_id, id) on delete restrict,
  constraint role_permissions_granted_by_membership_tenant_fk foreign key (
    organization_id, granted_by_membership_id
  ) references public.organization_memberships (organization_id, id) on delete restrict
);

create index role_permissions_organization_permission_role_idx
  on public.role_permissions (organization_id, permission_code, role_id);
create index role_permissions_granted_by_membership_idx
  on public.role_permissions (granted_by_membership_id)
  where granted_by_membership_id is not null;

create table public.role_assignments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  membership_id uuid not null,
  role_id uuid not null,
  scope_type text not null default 'organization',
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  revoked_at timestamptz,
  revoked_by_membership_id uuid,
  created_at timestamptz not null default now(),
  created_by_membership_id uuid,
  constraint role_assignments_organization_id_id_key unique (organization_id, id),
  constraint role_assignments_organization_membership_role_scope_key unique (
    organization_id, membership_id, role_id, scope_type
  ),
  constraint role_assignments_membership_tenant_fk foreign key (organization_id, membership_id)
    references public.organization_memberships (organization_id, id) on delete restrict,
  constraint role_assignments_role_tenant_fk foreign key (organization_id, role_id)
    references public.roles (organization_id, id) on delete restrict,
  constraint role_assignments_revoked_by_membership_tenant_fk foreign key (
    organization_id, revoked_by_membership_id
  ) references public.organization_memberships (organization_id, id) on delete restrict,
  constraint role_assignments_created_by_membership_tenant_fk foreign key (
    organization_id, created_by_membership_id
  ) references public.organization_memberships (organization_id, id) on delete restrict,
  constraint role_assignments_scope_type check (scope_type = 'organization'),
  constraint role_assignments_validity check (
    valid_until is null or valid_until > valid_from
  ),
  constraint role_assignments_revocation_after_creation check (
    revoked_at is null or revoked_at >= created_at
  )
);

create index role_assignments_effective_membership_idx
  on public.role_assignments (organization_id, membership_id, valid_from, valid_until)
  where revoked_at is null;
create index role_assignments_role_idx
  on public.role_assignments (organization_id, role_id);

create trigger organizations_set_updated_at before update on public.organizations
  for each row execute function public.set_updated_at();
create trigger profiles_set_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();
create trigger organization_memberships_set_updated_at before update on public.organization_memberships
  for each row execute function public.set_updated_at();
create trigger roles_set_updated_at before update on public.roles
  for each row execute function public.set_updated_at();

create or replace function public.enforce_system_permission_composition()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  permission_policy text;
  role_protected_kind text;
begin
  select delegation_policy
    into permission_policy
    from public.permission_catalog
   where code = new.permission_code;

  if permission_policy = 'system_only' then
    select protected_kind
      into role_protected_kind
      from public.roles
     where id = new.role_id
       and organization_id = new.organization_id;

    if role_protected_kind is distinct from 'demo_administrator' then
      raise exception 'system-only permissions require the protected demo administrator role'
        using errcode = 'P0001';
    end if;
  end if;

  return new;
end;
$$;

create trigger role_permissions_enforce_system_only
  before insert or update of organization_id, role_id, permission_code
  on public.role_permissions
  for each row execute function public.enforce_system_permission_composition();

create or replace function public.prevent_protected_role_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (tg_op = 'DELETE' and old.protected_kind is not null)
     or (tg_op = 'UPDATE' and (
       old.protected_kind is not null
       or new.protected_kind is distinct from old.protected_kind
     )) then
    raise exception 'protected roles are immutable outside a dedicated server operation'
      using errcode = 'P0001';
  end if;

  return coalesce(new, old);
end;
$$;

create trigger roles_prevent_protected_mutation
  before update or delete on public.roles
  for each row execute function public.prevent_protected_role_mutation();

insert into public.organizations (slug, display_name, status, timezone)
values ('demo-hospital', 'Hospital de demostración', 'active', 'America/Santiago')
on conflict (slug) do nothing;

insert into public.permission_catalog (
  code, family, description, delegation_policy
) values
  ('iam.membership.read', 'iam', 'List organization profiles and memberships.', 'ordinary'),
  ('iam.membership.manage', 'iam', 'Manage organization memberships through a server operation.', 'ordinary'),
  ('iam.role.read', 'iam', 'Read roles, permissions, and role assignments.', 'ordinary'),
  ('iam.role.manage', 'iam', 'Manage local role composition through a server operation.', 'ordinary'),
  ('iam.role.assign', 'iam', 'Assign and revoke local roles through a server operation.', 'ordinary'),
  ('org.unit.read', 'org', 'Read organizational units.', 'ordinary'),
  ('org.unit.manage', 'org', 'Manage organizational units through a server operation.', 'ordinary'),
  ('clinical.census.read', 'clinical', 'Read the clinical census.', 'ordinary'),
  ('clinical.patient.read', 'clinical', 'Read minimum patient demographics.', 'ordinary'),
  ('clinical.patient.identifier.read', 'clinical', 'Read patient identifiers.', 'ordinary'),
  ('clinical.timeline.read', 'clinical', 'Read clinical timelines.', 'ordinary'),
  ('clinical.condition.read', 'clinical', 'Read conditions.', 'ordinary'),
  ('clinical.medication.read', 'clinical', 'Read medication requests.', 'ordinary'),
  ('clinical.observation.read', 'clinical', 'Read observations.', 'ordinary'),
  ('clinical.procedure.read', 'clinical', 'Read procedures.', 'ordinary'),
  ('clinical.document.read', 'clinical', 'Read clinical documents.', 'ordinary'),
  ('clinical.provenance.read', 'clinical', 'Read clinical provenance metadata.', 'ordinary'),
  ('clinical.assigned.read', 'clinical', 'Satisfy the assigned-clinician access condition.', 'ordinary'),
  ('clinical.organization.read', 'clinical', 'Reserved organization-wide clinical read.', 'system_only'),
  ('clinical.assignment.manage', 'clinical', 'Manage care assignments through a server operation.', 'ordinary'),
  ('context.note.read', 'context', 'Read confirmed context notes.', 'ordinary'),
  ('context.note.create', 'context', 'Create context-note drafts.', 'ordinary'),
  ('context.note.confirm', 'context', 'Confirm context notes.', 'ordinary'),
  ('context.note.correct', 'context', 'Correct context notes append-only.', 'ordinary'),
  ('audit.read', 'audit', 'Read organization audit events.', 'ordinary'),
  ('integration.source.read', 'integration', 'Read source-system metadata.', 'ordinary'),
  ('integration.source.manage', 'integration', 'Manage source systems through a server operation.', 'ordinary'),
  ('integration.run.read', 'integration', 'Read sanitized ingestion runs.', 'ordinary')
on conflict (code) do nothing;

insert into public.roles (
  organization_id, name, description, is_system, protected_kind
)
select id, 'Administrador protegido', 'Rol seed protegido para la administración de demostración.', true, 'demo_administrator'
from public.organizations
where slug = 'demo-hospital'
on conflict do nothing;

insert into public.roles (organization_id, name, description, is_system)
select id, 'Personal clínico', 'Rol seed para personal clínico sujeto a asignaciones asistenciales futuras.', true
from public.organizations
where slug = 'demo-hospital'
on conflict do nothing;

insert into public.role_permissions (organization_id, role_id, permission_code)
select role.organization_id, role.id, permission.code
from public.roles role
join public.organizations organization on organization.id = role.organization_id
join (
  values
    ('iam.membership.read'),
    ('iam.membership.manage'),
    ('iam.role.read'),
    ('iam.role.manage'),
    ('iam.role.assign'),
    ('org.unit.read'),
    ('clinical.organization.read'),
    ('clinical.census.read'),
    ('clinical.patient.read'),
    ('clinical.timeline.read'),
    ('clinical.assignment.manage')
) as permission(code) on true
where organization.slug = 'demo-hospital'
  and role.protected_kind = 'demo_administrator'
on conflict do nothing;

insert into public.role_permissions (organization_id, role_id, permission_code)
select role.organization_id, role.id, permission.code
from public.roles role
join public.organizations organization on organization.id = role.organization_id
join (
  values
    ('clinical.assigned.read'),
    ('clinical.census.read'),
    ('clinical.patient.read'),
    ('clinical.timeline.read')
) as permission(code) on true
where organization.slug = 'demo-hospital'
  and role.name = 'Personal clínico'
on conflict do nothing;

create or replace function public.bootstrap_legacy_practitioner_iam()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  demo_organization_id uuid;
  administrator_role_id uuid;
  clinician_role_id uuid;
begin
  select id into strict demo_organization_id
  from public.organizations
  where slug = 'demo-hospital';

  select id into strict administrator_role_id
  from public.roles
  where organization_id = demo_organization_id
    and protected_kind = 'demo_administrator';

  select id into strict clinician_role_id
  from public.roles
  where organization_id = demo_organization_id
    and name = 'Personal clínico';

  insert into public.profiles (auth_user_id, display_name, status, created_at, updated_at)
  select practitioner.id,
         practitioner.display_name,
         case when practitioner.status = 'active' then 'active' else 'suspended' end,
         practitioner.created_at,
         practitioner.updated_at
  from public.practitioners practitioner
  on conflict (auth_user_id) do nothing;

  insert into public.organization_memberships (
    organization_id, profile_id, status, valid_from, created_at, updated_at
  )
  select demo_organization_id,
         profile.id,
         case when practitioner.status = 'active' then 'active' else 'suspended' end,
         practitioner.created_at,
         practitioner.created_at,
         practitioner.updated_at
  from public.practitioners practitioner
  join public.profiles profile on profile.auth_user_id = practitioner.id
  on conflict (organization_id, profile_id) do nothing;

  insert into public.role_assignments (
    organization_id, membership_id, role_id, valid_from, created_at
  )
  select demo_organization_id,
         membership.id,
         administrator_role_id,
         practitioner.created_at,
         practitioner.created_at
  from public.practitioners practitioner
  join public.profiles profile on profile.auth_user_id = practitioner.id
  join public.organization_memberships membership
    on membership.profile_id = profile.id
   and membership.organization_id = demo_organization_id
  where practitioner.role = 'administrator'
  on conflict (organization_id, membership_id, role_id, scope_type) do nothing;

  insert into public.role_assignments (
    organization_id, membership_id, role_id, valid_from, created_at
  )
  select demo_organization_id,
         membership.id,
         clinician_role_id,
         practitioner.created_at,
         practitioner.created_at
  from public.practitioners practitioner
  join public.profiles profile on profile.auth_user_id = practitioner.id
  join public.organization_memberships membership
    on membership.profile_id = profile.id
   and membership.organization_id = demo_organization_id
  where practitioner.role in ('physician', 'nurse')
    and practitioner.status = 'active'
  on conflict (organization_id, membership_id, role_id, scope_type) do nothing;
end;
$$;

select public.bootstrap_legacy_practitioner_iam();

create or replace function public.iam_current_profile_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select profile.id
  from public.profiles profile
  where profile.auth_user_id = auth.uid()
    and profile.status = 'active'
$$;

create or replace function public.has_active_organization_membership(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.profile_id
    where membership.organization_id = p_organization_id
      and profile.auth_user_id = auth.uid()
      and profile.status = 'active'
      and membership.status = 'active'
      and membership.valid_from <= now()
      and (membership.valid_until is null or membership.valid_until > now())
  )
$$;

create or replace function public.has_active_iam_permission(
  p_organization_id uuid,
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
    from public.profiles profile
    join public.organization_memberships membership on membership.profile_id = profile.id
    join public.role_assignments assignment
      on assignment.organization_id = membership.organization_id
     and assignment.membership_id = membership.id
    join public.roles role
      on role.organization_id = assignment.organization_id
     and role.id = assignment.role_id
    join public.role_permissions role_permission
      on role_permission.organization_id = role.organization_id
     and role_permission.role_id = role.id
    join public.permission_catalog permission on permission.code = role_permission.permission_code
    where profile.auth_user_id = auth.uid()
      and profile.status = 'active'
      and membership.organization_id = p_organization_id
      and membership.status = 'active'
      and membership.valid_from <= now()
      and (membership.valid_until is null or membership.valid_until > now())
      and assignment.scope_type = 'organization'
      and assignment.revoked_at is null
      and assignment.valid_from <= now()
      and (assignment.valid_until is null or assignment.valid_until > now())
      and role.status = 'active'
      and permission.code = p_permission_code
      and permission.status = 'active'
  )
$$;

create or replace function public.is_current_active_membership(p_membership_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.organization_memberships membership
    join public.profiles profile on profile.id = membership.profile_id
    where membership.id = p_membership_id
      and profile.auth_user_id = auth.uid()
      and profile.status = 'active'
      and membership.status = 'active'
      and membership.valid_from <= now()
      and (membership.valid_until is null or membership.valid_until > now())
  )
$$;

alter table public.organizations enable row level security;
alter table public.profiles enable row level security;
alter table public.organization_memberships enable row level security;
alter table public.permission_catalog enable row level security;
alter table public.roles enable row level security;
alter table public.role_permissions enable row level security;
alter table public.role_assignments enable row level security;

create policy "active members read their organizations" on public.organizations
  for select to authenticated
  using (public.has_active_organization_membership(id));

create policy "users read their own profiles" on public.profiles
  for select to authenticated
  using (auth_user_id = auth.uid());

create policy "members read own or authorized memberships" on public.organization_memberships
  for select to authenticated
  using (
    public.is_current_active_membership(id)
    or public.has_active_iam_permission(organization_id, 'iam.membership.read')
  );

create policy "active profiles read permission catalog" on public.permission_catalog
  for select to authenticated
  using (public.iam_current_profile_id() is not null);

create policy "authorized members read roles" on public.roles
  for select to authenticated
  using (public.has_active_iam_permission(organization_id, 'iam.role.read'));

create policy "authorized members read role permissions" on public.role_permissions
  for select to authenticated
  using (public.has_active_iam_permission(organization_id, 'iam.role.read'));

create policy "members read own or authorized role assignments" on public.role_assignments
  for select to authenticated
  using (
    public.is_current_active_membership(membership_id)
    or public.has_active_iam_permission(organization_id, 'iam.role.read')
  );

revoke all on table public.organizations,
  public.profiles,
  public.organization_memberships,
  public.permission_catalog,
  public.roles,
  public.role_permissions,
  public.role_assignments from public, anon, authenticated;

grant select on table public.organizations,
  public.profiles,
  public.organization_memberships,
  public.permission_catalog,
  public.roles,
  public.role_permissions,
  public.role_assignments to authenticated;

revoke all on function public.bootstrap_legacy_practitioner_iam() from public, anon, authenticated;
revoke all on function public.iam_current_profile_id() from public, anon;
revoke all on function public.has_active_organization_membership(uuid) from public, anon;
revoke all on function public.has_active_iam_permission(uuid, text) from public, anon;
revoke all on function public.is_current_active_membership(uuid) from public, anon;
revoke all on function public.enforce_system_permission_composition() from public, anon, authenticated;
revoke all on function public.prevent_protected_role_mutation() from public, anon, authenticated;

grant execute on function public.iam_current_profile_id() to authenticated;
grant execute on function public.has_active_organization_membership(uuid) to authenticated;
grant execute on function public.has_active_iam_permission(uuid, text) to authenticated;
grant execute on function public.is_current_active_membership(uuid) to authenticated;

comment on function public.bootstrap_legacy_practitioner_iam() is
  'Migration/seed-only bridge for legacy synthetic practitioners. Runtime callers have no EXECUTE privilege.';
comment on table public.role_assignments is
  'Phase 1 supports organization scope only. Unit scope is introduced with units in a later migration.';
comment on table public.roles is
  'The protected demo administrator role is immutable in phase 1. A later audited server operation must enforce the last-effective-administrator invariant when management is enabled.';
