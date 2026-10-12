-- Runtime roles, including service_role, cannot alter the platform permission catalog.
create or replace function public.protect_permission_catalog()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user <> 'postgres' then
    raise exception 'permission catalog is migration-managed'
      using errcode = 'P0001';
  end if;
  return coalesce(new, old);
end;
$$;

create trigger permission_catalog_migration_only
  before insert or update or delete on public.permission_catalog
  for each row execute function public.protect_permission_catalog();

revoke all on function public.protect_permission_catalog() from public, anon, authenticated;

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
    join public.profiles profile on profile.id = membership.profile_id
    join public.roles role
      on role.organization_id = organization.id
    where organization.id = new.organization_id
      and organization.status = 'active'
      and membership.id = new.membership_id
      and membership.status = 'active'
      and membership.valid_from <= now()
      and (membership.valid_until is null or membership.valid_until > now())
      and profile.status = 'active'
      and role.id = new.role_id
      and role.status = 'active'
  ) then
    raise exception 'new role assignments require an active organization, profile, membership, and role'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function public.enforce_role_assignment_preconditions() from public, anon, authenticated;
