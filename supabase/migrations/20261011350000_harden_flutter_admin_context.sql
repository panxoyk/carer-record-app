-- Correct the 4.3 read boundary without changing earlier migrations.
drop policy if exists "authorized members read tenant profiles" on public.profiles;

create or replace view public.iam_current_context
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
  select pc.code
  from public.permission_catalog pc
  where pc.status = 'active'
    and public.has_active_iam_permission(m.organization_id, pc.code)
) permission on true
where p.id = public.iam_current_profile_id()
  and p.status = 'active'
  and m.status = 'active'
  and m.valid_from <= now()
  and (m.valid_until is null or m.valid_until > now())
  and o.status = 'active';

create or replace view public.iam_role_directory
with (security_invoker = true, security_barrier = true)
as
select r.organization_id, r.id as role_id, r.name as role_name, r.description,
       r.status as role_status, r.protected_kind, pc.code as permission_code
from public.roles r
left join public.role_permissions rp
  on rp.organization_id = r.organization_id and rp.role_id = r.id
left join public.permission_catalog pc on pc.code = rp.permission_code and pc.status = 'active'
where r.protected_kind is null and r.status = 'active'
  and public.has_active_iam_permission(r.organization_id, 'iam.role.read');

create or replace view public.iam_member_directory
with (security_invoker = true, security_barrier = true)
as
select m.organization_id, m.id as membership_id, p.id as profile_id,
       p.display_name, p.status as profile_status, m.status as membership_status,
       m.valid_from, m.valid_until
from public.organization_memberships m
join public.profiles p on p.id = m.profile_id
join public.organizations o on o.id = m.organization_id
where public.has_active_iam_permission(m.organization_id, 'iam.membership.read')
  and o.status = 'active' and p.status = 'active' and m.status = 'active'
  and m.valid_from <= now() and (m.valid_until is null or m.valid_until > now());

create or replace view public.iam_member_role_assignments
with (security_invoker = true, security_barrier = true)
as
select ra.organization_id, ra.id as assignment_id, ra.membership_id, ra.role_id,
       r.name as role_name, r.protected_kind, ra.valid_from, ra.valid_until, ra.revoked_at
from public.role_assignments ra
join public.roles r on r.organization_id = ra.organization_id and r.id = ra.role_id
join public.organization_memberships m
  on m.organization_id = ra.organization_id and m.id = ra.membership_id
join public.profiles p on p.id = m.profile_id
join public.organizations o on o.id = m.organization_id
where r.protected_kind is null and r.status = 'active'
  and m.status = 'active' and m.valid_from <= now()
  and (m.valid_until is null or m.valid_until > now())
  and p.status = 'active' and o.status = 'active'
  and public.has_active_iam_permission(ra.organization_id, 'iam.membership.read');

create or replace view public.iam_assignment_hospitalizations
with (security_invoker = true, security_barrier = true)
as
select h.organization_id, h.id as hospitalization_id, h.status as hospitalization_status,
       h.admitted_at, h.discharged_at, ca.id as assignment_id, ca.membership_id,
       ca.valid_from as assignment_valid_from, ca.valid_until as assignment_valid_until,
       ca.revoked_at
from public.hospitalizations h
left join public.care_assignments ca
  on ca.organization_id = h.organization_id and ca.hospitalization_id = h.id
  and exists (
    select 1
    from public.organization_memberships assigned_membership
    join public.profiles assigned_profile on assigned_profile.id = assigned_membership.profile_id
    where assigned_membership.organization_id = ca.organization_id
      and assigned_membership.id = ca.membership_id
      and assigned_membership.status = 'active'
      and assigned_membership.valid_from <= now()
      and (assigned_membership.valid_until is null or assigned_membership.valid_until > now())
      and assigned_profile.status = 'active'
  )
  and exists (
    select 1
    from public.role_assignments assigned_role
    join public.roles assigned_catalog_role
      on assigned_catalog_role.organization_id = assigned_role.organization_id
     and assigned_catalog_role.id = assigned_role.role_id
    join public.role_permissions assigned_permission
      on assigned_permission.organization_id = assigned_catalog_role.organization_id
     and assigned_permission.role_id = assigned_catalog_role.id
    join public.permission_catalog assigned_permission_catalog
      on assigned_permission_catalog.code = assigned_permission.permission_code
     and assigned_permission_catalog.status = 'active'
    where assigned_role.organization_id = ca.organization_id
      and assigned_role.membership_id = ca.membership_id
      and assigned_role.revoked_at is null
      and assigned_role.valid_from <= now()
      and (assigned_role.valid_until is null or assigned_role.valid_until > now())
      and assigned_catalog_role.status = 'active'
      and assigned_permission.permission_code = 'clinical.assigned.read'
  )
where public.has_active_iam_permission(h.organization_id, 'clinical.assignment.manage')
  and h.status not in ('cancelled', 'entered_in_error');
