-- Correct phase 1 IAM invariants without rewriting the already-applied migration.

create or replace function public.validate_organization_timezone()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1 from pg_catalog.pg_timezone_names zone where zone.name = new.timezone
  ) then
    raise exception 'timezone must be a valid IANA timezone name'
      using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger organizations_validate_iana_timezone
  before insert or update of timezone on public.organizations
  for each row execute function public.validate_organization_timezone();
do $$
begin
  if exists (
    select 1 from public.organizations organization
    where not exists (
      select 1 from pg_catalog.pg_timezone_names zone where zone.name = organization.timezone
    )
  ) then
    raise exception 'existing organization timezone is not a valid IANA name';
  end if;
end;
$$;

alter table public.role_assignments
  drop constraint role_assignments_organization_membership_role_scope_key;

create extension if not exists btree_gist;
alter table public.role_assignments
  add constraint role_assignments_no_overlapping_equivalent_grants
  exclude using gist (
    organization_id with =,
    membership_id with =,
    role_id with =,
    scope_type with =,
    tstzrange(valid_from, valid_until, '[)') with &&
  ) where (revoked_at is null);

-- The original bridge named the unique constraint that is intentionally replaced
-- above. Keep its backfill idempotent without relying on that obsolete constraint.
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
  select id into strict demo_organization_id from public.organizations where slug = 'demo-hospital';
  select id into strict administrator_role_id from public.roles
    where organization_id = demo_organization_id and protected_kind = 'demo_administrator';
  select id into strict clinician_role_id from public.roles
    where organization_id = demo_organization_id and name = 'Personal clínico';

  insert into public.profiles (auth_user_id, display_name, status, created_at, updated_at)
  select practitioner.id, practitioner.display_name,
         case when practitioner.status = 'active' then 'active' else 'suspended' end,
         practitioner.created_at, practitioner.updated_at
  from public.practitioners practitioner
  on conflict (auth_user_id) do nothing;

  insert into public.organization_memberships (
    organization_id, profile_id, status, valid_from, created_at, updated_at
  )
  select demo_organization_id, profile.id,
         case when practitioner.status = 'active' then 'active' else 'suspended' end,
         practitioner.created_at, practitioner.created_at, practitioner.updated_at
  from public.practitioners practitioner
  join public.profiles profile on profile.auth_user_id = practitioner.id
  on conflict (organization_id, profile_id) do nothing;

  insert into public.role_assignments (
    organization_id, membership_id, role_id, valid_from, created_at
  )
  select demo_organization_id, membership.id, administrator_role_id,
         practitioner.created_at, practitioner.created_at
  from public.practitioners practitioner
  join public.profiles profile on profile.auth_user_id = practitioner.id
  join public.organization_memberships membership
    on membership.profile_id = profile.id and membership.organization_id = demo_organization_id
  where practitioner.role = 'administrator'
    and not exists (
      select 1 from public.role_assignments prior
      where prior.organization_id = demo_organization_id
        and prior.membership_id = membership.id and prior.role_id = administrator_role_id
    );

  insert into public.role_assignments (
    organization_id, membership_id, role_id, valid_from, created_at
  )
  select demo_organization_id, membership.id, clinician_role_id,
         practitioner.created_at, practitioner.created_at
  from public.practitioners practitioner
  join public.profiles profile on profile.auth_user_id = practitioner.id
  join public.organization_memberships membership
    on membership.profile_id = profile.id and membership.organization_id = demo_organization_id
  where practitioner.role in ('physician', 'nurse') and practitioner.status = 'active'
    and not exists (
      select 1 from public.role_assignments prior
      where prior.organization_id = demo_organization_id
        and prior.membership_id = membership.id and prior.role_id = clinician_role_id
    );
end;
$$;
revoke all on function public.bootstrap_legacy_practitioner_iam() from public, anon, authenticated;

create or replace function public.enforce_role_permission_invariants()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  target_role public.roles%rowtype;
  target_permission public.permission_catalog%rowtype;
begin
  select * into target_role
  from public.roles
  where id = new.role_id and organization_id = new.organization_id;

  if target_role.protected_kind = 'demo_administrator' and current_user <> 'postgres' then
    raise exception 'protected administrator composition is migration-managed'
      using errcode = 'P0001';
  end if;

  select * into target_permission
  from public.permission_catalog
  where code = new.permission_code;

  if target_role.status <> 'active' then
    raise exception 'permissions cannot be granted to an inactive role'
      using errcode = '23514';
  end if;
  if target_permission.status <> 'active' then
    raise exception 'deprecated permissions cannot be newly granted'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create or replace function public.protect_role_permission_history()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  target_role public.roles%rowtype;
begin
  if tg_op = 'DELETE' or tg_op = 'UPDATE' then
    select * into target_role
    from public.roles
    where id = old.role_id and organization_id = old.organization_id;
    if target_role.protected_kind = 'demo_administrator' and current_user <> 'postgres' then
      raise exception 'protected administrator composition is migration-managed'
        using errcode = 'P0001';
    end if;
  end if;
  if tg_op = 'UPDATE' then
    select * into target_role
    from public.roles
    where id = new.role_id and organization_id = new.organization_id;
    if target_role.protected_kind = 'demo_administrator' and current_user <> 'postgres' then
      raise exception 'protected administrator composition is migration-managed'
        using errcode = 'P0001';
    end if;
  end if;
  return coalesce(new, old);
end;
$$;

create trigger role_permissions_enforce_phase1_invariants
  before insert or update of organization_id, role_id, permission_code
  on public.role_permissions
  for each row execute function public.enforce_role_permission_invariants();
create trigger role_permissions_protect_phase1_history
  before update or delete on public.role_permissions
  for each row execute function public.protect_role_permission_history();

create or replace function public.enforce_role_assignment_preconditions()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.organizations organization
    join public.organization_memberships membership
      on membership.organization_id = organization.id
    join public.roles role
      on role.organization_id = organization.id
    where organization.id = new.organization_id
      and organization.status = 'active'
      and membership.id = new.membership_id
      and membership.status = 'active'
      and membership.valid_from <= now()
      and (membership.valid_until is null or membership.valid_until > now())
      and role.id = new.role_id
      and role.status = 'active'
  ) then
    raise exception 'new role assignments require an active organization, membership, and role'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger role_assignments_require_active_authority
  before insert on public.role_assignments
  for each row execute function public.enforce_role_assignment_preconditions();

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
    join public.organizations organization on organization.id = membership.organization_id
    where membership.organization_id = p_organization_id
      and organization.status = 'active'
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
    from public.organizations organization
    join public.profiles profile on profile.auth_user_id = auth.uid()
    join public.organization_memberships membership
      on membership.profile_id = profile.id and membership.organization_id = organization.id
    join public.role_assignments assignment
      on assignment.organization_id = membership.organization_id
     and assignment.membership_id = membership.id
    join public.roles role
      on role.organization_id = assignment.organization_id and role.id = assignment.role_id
    join public.role_permissions role_permission
      on role_permission.organization_id = role.organization_id and role_permission.role_id = role.id
    join public.permission_catalog permission on permission.code = role_permission.permission_code
    where organization.id = p_organization_id
      and organization.status = 'active'
      and profile.status = 'active'
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
    join public.organizations organization on organization.id = membership.organization_id
    where membership.id = p_membership_id
      and organization.status = 'active'
      and profile.auth_user_id = auth.uid()
      and profile.status = 'active'
      and membership.status = 'active'
      and membership.valid_from <= now()
      and (membership.valid_until is null or membership.valid_until > now())
  )
$$;

drop policy "users read their own profiles" on public.profiles;
create policy "users read own or tenant-authorized profile metadata" on public.profiles
  for select to authenticated
  using (
    auth_user_id = auth.uid()
    or exists (
      select 1
      from public.organization_memberships target_membership
      where target_membership.profile_id = profiles.id
        and public.has_active_iam_permission(
          target_membership.organization_id, 'iam.membership.read'
        )
    )
  );

revoke select on public.profiles from authenticated;
grant select (id, display_name, status) on public.profiles to authenticated;

revoke all on function public.enforce_role_permission_invariants() from public, anon, authenticated;
revoke all on function public.protect_role_permission_history() from public, anon, authenticated;
revoke all on function public.enforce_role_assignment_preconditions() from public, anon, authenticated;
revoke all on function public.validate_organization_timezone() from public, anon, authenticated;
