-- Complete the protected demo administrator's delivered-feature permission set.
-- This permission alone never grants clinical rows; RLS still requires the reserved
-- clinical.organization.read route (or a clinician's care assignment).
insert into public.role_permissions(organization_id,role_id,permission_code)
select role.organization_id,role.id,'clinical.assigned.read'
from public.roles role
where role.protected_kind='demo_administrator'
on conflict (role_id,permission_code) do nothing;

comment on table public.role_permissions is
  'Role composition is migration-managed for the protected administrator; ordinary composition and assignment use audited, authority-checked IAM operations.';
