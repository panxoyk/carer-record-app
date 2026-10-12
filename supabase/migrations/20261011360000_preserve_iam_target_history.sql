-- Keep target history visible to authorized actors; eligibility remains active-only.
create policy "membership readers inspect tenant profile metadata" on public.profiles
  for select to authenticated
  using (
    exists (
      select 1 from public.organization_memberships target_membership
      where target_membership.profile_id = profiles.id
        and (
          public.has_active_iam_permission(
            target_membership.organization_id, 'iam.membership.read'
          )
          or public.has_active_iam_permission(
            target_membership.organization_id, 'clinical.assignment.manage'
          )
        )
    )
  );

create policy "membership readers inspect role history" on public.roles
  for select to authenticated
  using (
    public.has_active_iam_permission(organization_id, 'iam.membership.read')
    or public.has_active_iam_permission(organization_id, 'clinical.assignment.manage')
  );

create policy "assignment managers inspect tenant memberships" on public.organization_memberships
  for select to authenticated
  using (public.has_active_iam_permission(organization_id, 'clinical.assignment.manage'));

create policy "assignment managers inspect role composition" on public.role_permissions
  for select to authenticated
  using (public.has_active_iam_permission(organization_id, 'clinical.assignment.manage'));

create policy "membership readers inspect role assignment history" on public.role_assignments
  for select to authenticated
  using (
    public.has_active_iam_permission(organization_id, 'iam.membership.read')
    or public.has_active_iam_permission(organization_id, 'clinical.assignment.manage')
  );

create or replace view public.iam_member_directory
with (security_invoker = true, security_barrier = true)
as
select m.organization_id, m.id as membership_id, p.id as profile_id,
       p.display_name, p.status as profile_status, m.status as membership_status,
       m.valid_from, m.valid_until
from public.organization_memberships m
join public.profiles p on p.id = m.profile_id
where public.has_active_iam_permission(m.organization_id, 'iam.membership.read');

create or replace view public.iam_member_role_assignments
with (security_invoker = true, security_barrier = true)
as
select ra.organization_id, ra.id as assignment_id, ra.membership_id, ra.role_id,
       r.name as role_name, r.protected_kind, ra.valid_from, ra.valid_until, ra.revoked_at
from public.role_assignments ra
join public.roles r on r.organization_id = ra.organization_id and r.id = ra.role_id
where r.protected_kind is null
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
where public.has_active_iam_permission(h.organization_id, 'clinical.assignment.manage')
  and h.status not in ('cancelled', 'entered_in_error');

create or replace view public.iam_assignment_eligible_members
with (security_invoker = true, security_barrier = true)
as
select distinct m.organization_id, m.id as membership_id, p.display_name
from public.organization_memberships m
join public.profiles p on p.id = m.profile_id
join public.role_assignments ra on ra.organization_id = m.organization_id and ra.membership_id = m.id
join public.roles r on r.organization_id = ra.organization_id and r.id = ra.role_id
join public.role_permissions rp on rp.organization_id = r.organization_id and rp.role_id = r.id
join public.permission_catalog pc on pc.code = rp.permission_code and pc.status = 'active'
where p.status = 'active' and m.status = 'active' and m.valid_from <= now()
  and (m.valid_until is null or m.valid_until > now())
  and m.profile_id <> public.iam_current_profile_id()
  and ra.revoked_at is null and ra.valid_from <= now()
  and (ra.valid_until is null or ra.valid_until > now())
  and r.status = 'active'
  and pc.code = 'clinical.assigned.read'
  and public.has_active_iam_permission(m.organization_id, 'clinical.assignment.manage');
