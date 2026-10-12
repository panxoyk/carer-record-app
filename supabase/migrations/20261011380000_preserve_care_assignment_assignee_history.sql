-- Keep historical care-assignment targets identifiable to authorized managers.
-- Eligibility for new assignments remains the separate active-only contract.
create or replace view public.iam_assignment_hospitalizations
with (security_invoker = true, security_barrier = true)
as
select h.organization_id, h.id as hospitalization_id, h.status as hospitalization_status,
       h.admitted_at, h.discharged_at, ca.id as assignment_id, ca.membership_id,
       ca.valid_from as assignment_valid_from, ca.valid_until as assignment_valid_until,
       ca.revoked_at, assigned_profile.display_name as assignee_display_name,
       assigned_membership.status as assignee_membership_status
from public.hospitalizations h
left join public.care_assignments ca
  on ca.organization_id = h.organization_id and ca.hospitalization_id = h.id
left join public.organization_memberships assigned_membership
  on assigned_membership.organization_id = ca.organization_id
 and assigned_membership.id = ca.membership_id
left join public.profiles assigned_profile
  on assigned_profile.id = assigned_membership.profile_id
where public.has_active_iam_permission(h.organization_id, 'clinical.assignment.manage')
  and h.status not in ('cancelled', 'entered_in_error');
