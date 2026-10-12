-- Limit auxiliary history policies to ordinary-role rows. Existing iam.role.read
-- policies remain unchanged and continue to grant their prior contract.
drop policy if exists "membership readers inspect role history" on public.roles;
create policy "membership readers inspect role history" on public.roles
  for select to authenticated
  using (
    protected_kind is null
    and (
      public.has_active_iam_permission(organization_id, 'iam.membership.read')
      or public.has_active_iam_permission(organization_id, 'clinical.assignment.manage')
    )
  );

drop policy if exists "assignment managers inspect role composition" on public.role_permissions;
create policy "assignment managers inspect role composition" on public.role_permissions
  for select to authenticated
  using (
    exists (
      select 1 from public.roles ordinary_role
      where ordinary_role.organization_id = role_permissions.organization_id
        and ordinary_role.id = role_permissions.role_id
        and ordinary_role.protected_kind is null
    )
    and (
      public.has_active_iam_permission(organization_id, 'clinical.assignment.manage')
      or public.has_active_iam_permission(organization_id, 'iam.membership.read')
    )
  );

drop policy if exists "membership readers inspect role assignment history" on public.role_assignments;
create policy "membership readers inspect role assignment history" on public.role_assignments
  for select to authenticated
  using (
    exists (
      select 1 from public.roles ordinary_role
      where ordinary_role.organization_id = role_assignments.organization_id
        and ordinary_role.id = role_assignments.role_id
        and ordinary_role.protected_kind is null
    )
    and (
      public.has_active_iam_permission(organization_id, 'iam.membership.read')
      or public.has_active_iam_permission(organization_id, 'clinical.assignment.manage')
    )
  );
