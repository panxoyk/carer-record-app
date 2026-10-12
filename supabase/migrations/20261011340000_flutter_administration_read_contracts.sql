-- Phase 4.3 typed, tenant-scoped read contracts for the Flutter client.
-- No auth identifiers, contact data, local identifiers, or clinical payloads leave SQL.

create policy "authorized members read tenant profiles" on public.profiles
  for select to authenticated
  using (
    exists (
      select 1 from public.organization_memberships m
      where m.profile_id = profiles.id
        and public.has_active_iam_permission(m.organization_id, 'iam.membership.read')
    )
  );

create view public.iam_current_context
with (security_invoker = true, security_barrier = true)
as
select o.id as organization_id, o.display_name as organization_name,
       p.id as profile_id, p.display_name, p.status as profile_status,
       m.id as membership_id, m.status as membership_status,
       permission.code as permission_code
from public.profiles p
join public.organization_memberships m on m.profile_id = p.id
join public.organizations o on o.id = m.organization_id
left join lateral (
  select distinct pc.code
  from public.role_assignments ra
  join public.roles r on r.id = ra.role_id and r.organization_id = ra.organization_id
  join public.role_permissions rp on rp.role_id = r.id and rp.organization_id = r.organization_id
  join public.permission_catalog pc on pc.code = rp.permission_code and pc.status = 'active'
  where ra.membership_id = m.id and ra.organization_id = m.organization_id
    and ra.revoked_at is null and ra.valid_from <= now() and (ra.valid_until is null or ra.valid_until > now())
    and r.status = 'active'
) permission on true
where p.id = public.iam_current_profile_id();

create view public.iam_member_directory
with (security_invoker = true, security_barrier = true)
as
select m.organization_id, m.id as membership_id, p.id as profile_id,
       p.display_name, p.status as profile_status, m.status as membership_status,
       m.valid_from, m.valid_until
from public.organization_memberships m
join public.profiles p on p.id = m.profile_id
where public.has_active_iam_permission(m.organization_id, 'iam.membership.read');

create view public.iam_role_directory
with (security_invoker = true, security_barrier = true)
as
select r.organization_id, r.id as role_id, r.name as role_name, r.description,
       r.status as role_status, r.protected_kind,
       pc.code as permission_code
from public.roles r
left join public.role_permissions rp on rp.organization_id = r.organization_id and rp.role_id = r.id
left join public.permission_catalog pc on pc.code = rp.permission_code and pc.status = 'active'
where public.has_active_iam_permission(r.organization_id, 'iam.role.read');

create view public.iam_member_role_assignments
with (security_invoker = true, security_barrier = true)
as
select ra.organization_id, ra.id as assignment_id, ra.membership_id, ra.role_id,
       r.name as role_name, r.protected_kind, ra.valid_from, ra.valid_until, ra.revoked_at
from public.role_assignments ra
join public.roles r on r.organization_id = ra.organization_id and r.id = ra.role_id
where public.has_active_iam_permission(ra.organization_id, 'iam.membership.read');

create view public.iam_assignment_hospitalizations
with (security_invoker = true, security_barrier = true)
as
select h.organization_id, h.id as hospitalization_id, h.status as hospitalization_status,
       h.admitted_at, h.discharged_at, ca.id as assignment_id, ca.membership_id,
       ca.valid_from as assignment_valid_from, ca.valid_until as assignment_valid_until,
       ca.revoked_at
from public.hospitalizations h
left join public.care_assignments ca
  on ca.organization_id = h.organization_id and ca.hospitalization_id = h.id
where public.has_active_iam_permission(h.organization_id, 'clinical.assignment.manage')
  and h.status not in ('cancelled', 'entered_in_error');

create view public.iam_assignment_eligible_members
with (security_invoker = true, security_barrier = true)
as
select distinct m.organization_id, m.id as membership_id, p.display_name
from public.organization_memberships m
join public.profiles p on p.id = m.profile_id
join public.role_assignments ra on ra.organization_id = m.organization_id and ra.membership_id = m.id
join public.roles r on r.organization_id = ra.organization_id and r.id = ra.role_id and r.status = 'active'
join public.role_permissions rp on rp.organization_id = r.organization_id and rp.role_id = r.id
where p.status = 'active' and m.status = 'active' and m.valid_from <= now()
  and (m.valid_until is null or m.valid_until > now())
  and m.profile_id <> public.iam_current_profile_id()
  and ra.revoked_at is null and ra.valid_from <= now() and (ra.valid_until is null or ra.valid_until > now())
  and rp.permission_code = 'clinical.assigned.read'
  and public.has_active_iam_permission(m.organization_id, 'clinical.assignment.manage');

revoke all on public.iam_current_context, public.iam_member_directory, public.iam_role_directory,
  public.iam_member_role_assignments, public.iam_assignment_hospitalizations,
  public.iam_assignment_eligible_members from public, anon;
grant select on public.iam_current_context, public.iam_member_directory, public.iam_role_directory,
  public.iam_member_role_assignments, public.iam_assignment_hospitalizations,
  public.iam_assignment_eligible_members to authenticated;
