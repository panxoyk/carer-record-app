begin;

create extension if not exists pgtap;

select plan(68);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
) values
  ('81000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'iam.admin@example.test', crypt('TestPassword123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('81000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'iam.suspended-profile@example.test', crypt('TestPassword123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('81000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'iam.suspended-membership@example.test', crypt('TestPassword123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('81000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'iam.inactive-role@example.test', crypt('TestPassword123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('81000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'iam.future@example.test', crypt('TestPassword123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('81000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'iam.expired@example.test', crypt('TestPassword123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('81000000-0000-0000-0000-000000000007', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'iam.revoked@example.test', crypt('TestPassword123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('81000000-0000-0000-0000-000000000008', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'iam.other-tenant@example.test', crypt('TestPassword123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '');

insert into public.organizations (id, slug, display_name) values
  ('82000000-0000-0000-0000-000000000001', 'iam-test-a', 'IAM test organization A'),
  ('82000000-0000-0000-0000-000000000002', 'iam-test-b', 'IAM test organization B');

insert into public.profiles (id, auth_user_id, display_name, status) values
  ('83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001', 'IAM Admin', 'active'),
  ('83000000-0000-0000-0000-000000000002', '81000000-0000-0000-0000-000000000002', 'Suspended profile', 'suspended'),
  ('83000000-0000-0000-0000-000000000003', '81000000-0000-0000-0000-000000000003', 'Suspended membership', 'active'),
  ('83000000-0000-0000-0000-000000000004', '81000000-0000-0000-0000-000000000004', 'Inactive role', 'active'),
  ('83000000-0000-0000-0000-000000000005', '81000000-0000-0000-0000-000000000005', 'Future assignment', 'active'),
  ('83000000-0000-0000-0000-000000000006', '81000000-0000-0000-0000-000000000006', 'Expired assignment', 'active'),
  ('83000000-0000-0000-0000-000000000007', '81000000-0000-0000-0000-000000000007', 'Revoked assignment', 'active'),
  ('83000000-0000-0000-0000-000000000008', '81000000-0000-0000-0000-000000000008', 'Other tenant', 'active');

insert into public.organization_memberships (id, organization_id, profile_id, status) values
  ('84000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', 'active'),
  ('84000000-0000-0000-0000-000000000002', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000002', 'active'),
  ('84000000-0000-0000-0000-000000000003', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000003', 'suspended'),
  ('84000000-0000-0000-0000-000000000004', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000004', 'active'),
  ('84000000-0000-0000-0000-000000000005', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000005', 'active'),
  ('84000000-0000-0000-0000-000000000006', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000006', 'active'),
  ('84000000-0000-0000-0000-000000000007', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000007', 'active'),
  ('84000000-0000-0000-0000-000000000008', '82000000-0000-0000-0000-000000000002', '83000000-0000-0000-0000-000000000008', 'active');

insert into public.roles (id, organization_id, name, description, status) values
  ('85000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000001', 'IAM test administrator', 'Reads IAM data in test organization A.', 'active'),
  ('85000000-0000-0000-0000-000000000002', '82000000-0000-0000-0000-000000000001', 'Inactive IAM role', 'Inactive IAM test role.', 'active'),
  ('85000000-0000-0000-0000-000000000003', '82000000-0000-0000-0000-000000000001', 'Future IAM role', 'Future IAM test role.', 'active'),
  ('85000000-0000-0000-0000-000000000004', '82000000-0000-0000-0000-000000000001', 'Expired IAM role', 'Expired IAM test role.', 'active'),
  ('85000000-0000-0000-0000-000000000005', '82000000-0000-0000-0000-000000000001', 'Revoked IAM role', 'Revoked IAM test role.', 'active'),
  ('85000000-0000-0000-0000-000000000006', '82000000-0000-0000-0000-000000000002', 'Other tenant IAM role', 'IAM test role in organization B.', 'active');

insert into public.role_permissions (organization_id, role_id, permission_code) values
  ('82000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000001', 'iam.membership.read'),
  ('82000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000001', 'iam.role.read'),
  ('82000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000002', 'iam.role.read'),
  ('82000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000003', 'iam.role.read'),
  ('82000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000004', 'iam.role.read'),
  ('82000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000005', 'iam.role.read'),
  ('82000000-0000-0000-0000-000000000002', '85000000-0000-0000-0000-000000000006', 'iam.role.read');

-- These legacy-style rows are fixtures; activation preconditions are tested below.
alter table public.role_assignments disable trigger role_assignments_require_active_authority;
insert into public.role_assignments (
  id, organization_id, membership_id, role_id, valid_from, valid_until, revoked_at
) values
  ('86000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000001', '84000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000001', now() - interval '1 day', null, null),
  ('86000000-0000-0000-0000-000000000002', '82000000-0000-0000-0000-000000000001', '84000000-0000-0000-0000-000000000002', '85000000-0000-0000-0000-000000000001', now() - interval '1 day', null, null),
  ('86000000-0000-0000-0000-000000000003', '82000000-0000-0000-0000-000000000001', '84000000-0000-0000-0000-000000000003', '85000000-0000-0000-0000-000000000001', now() - interval '1 day', null, null),
  ('86000000-0000-0000-0000-000000000004', '82000000-0000-0000-0000-000000000001', '84000000-0000-0000-0000-000000000004', '85000000-0000-0000-0000-000000000002', now() - interval '1 day', null, null),
  ('86000000-0000-0000-0000-000000000005', '82000000-0000-0000-0000-000000000001', '84000000-0000-0000-0000-000000000005', '85000000-0000-0000-0000-000000000003', now() + interval '1 day', null, null),
  ('86000000-0000-0000-0000-000000000006', '82000000-0000-0000-0000-000000000001', '84000000-0000-0000-0000-000000000006', '85000000-0000-0000-0000-000000000004', now() - interval '2 days', now() - interval '1 day', null),
  ('86000000-0000-0000-0000-000000000007', '82000000-0000-0000-0000-000000000001', '84000000-0000-0000-0000-000000000007', '85000000-0000-0000-0000-000000000005', now() - interval '1 day', null, null),
  ('86000000-0000-0000-0000-000000000008', '82000000-0000-0000-0000-000000000002', '84000000-0000-0000-0000-000000000008', '85000000-0000-0000-0000-000000000006', now() - interval '1 day', null, null);
alter table public.role_assignments enable trigger role_assignments_require_active_authority;

update public.roles set status = 'inactive'
where id = '85000000-0000-0000-0000-000000000002';

set local role anon;
select ok(not has_table_privilege('anon', 'public.organizations', 'select'), 'anon has no organization read grant');
select ok(not has_table_privilege('anon', 'public.permission_catalog', 'select'), 'anon has no permission-catalog read grant');
select ok(not has_function_privilege('anon', 'public.has_active_iam_permission(uuid, text)', 'execute'), 'anon cannot execute IAM authorization helpers');
select throws_ok(
  $$insert into public.organizations (slug, display_name) values ('anon-elevation', 'Must fail.')$$,
  '42501',
  'permission denied for table organizations',
  'anon cannot create an organization'
);
reset role;

select ok(not has_function_privilege('authenticated', 'public.bootstrap_legacy_practitioner_iam()', 'execute'), 'authenticated users cannot invoke the legacy bootstrap bridge');

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000099', true);
select is((select count(*) from public.organizations), 0::bigint, 'an authenticated user without a profile cannot read organizations');
select throws_ok(
  $$insert into public.roles (organization_id, name, description) values ('82000000-0000-0000-0000-000000000001', 'Self elevation', 'Must fail.')$$,
  '42501',
  'permission denied for table roles',
  'an authenticated user cannot create a role directly'
);
reset role;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
) values
  ('81000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'upgrade.admin@example.test', crypt('TestPassword123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('81000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'upgrade.physician@example.test', crypt('TestPassword123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('81000000-0000-0000-0000-000000000103', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'upgrade.nurse@example.test', crypt('TestPassword123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('81000000-0000-0000-0000-000000000104', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'upgrade.technician@example.test', crypt('TestPassword123!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '');

insert into public.practitioners (id, display_name, role, status) values
  ('81000000-0000-0000-0000-000000000101', 'Upgrade administrator', 'administrator', 'active'),
  ('81000000-0000-0000-0000-000000000102', 'Upgrade physician', 'physician', 'active'),
  ('81000000-0000-0000-0000-000000000103', 'Upgrade nurse', 'nurse', 'active'),
  ('81000000-0000-0000-0000-000000000104', 'Upgrade technician', 'technician', 'active');

select lives_ok('select public.bootstrap_legacy_practitioner_iam()', 'the upgrade bridge backfills a synthetic legacy fixture');
select lives_ok('select public.bootstrap_legacy_practitioner_iam()', 'the upgrade bridge is idempotent');
select is(
  (select count(*) from public.role_assignments assignment
   join public.organization_memberships membership on membership.id = assignment.membership_id
   join public.profiles profile on profile.id = membership.profile_id
   join public.roles role on role.id = assignment.role_id
   where profile.auth_user_id = '81000000-0000-0000-0000-000000000101'
     and role.protected_kind = 'demo_administrator'),
  1::bigint,
  'the upgrade bridge maps an active legacy administrator to the protected role'
);
select is(
  (select count(*) from public.role_assignments assignment
   join public.organization_memberships membership on membership.id = assignment.membership_id
   join public.profiles profile on profile.id = membership.profile_id
   join public.roles role on role.id = assignment.role_id
   where profile.auth_user_id in ('81000000-0000-0000-0000-000000000102', '81000000-0000-0000-0000-000000000103')
     and role.name = 'Personal clínico'),
  2::bigint,
  'the upgrade bridge maps active legacy physician and nurse accounts to Personal clínico'
);
select is(
  (select count(*) from public.role_assignments assignment
   join public.organization_memberships membership on membership.id = assignment.membership_id
   join public.profiles profile on profile.id = membership.profile_id
   where profile.auth_user_id = '81000000-0000-0000-0000-000000000104'),
  0::bigint,
  'the upgrade bridge gives a legacy technician no new role'
);
select is(
  (select count(*) from public.organization_memberships membership
   join public.profiles profile on profile.id = membership.profile_id
   where profile.auth_user_id = '81000000-0000-0000-0000-000000000104'),
  1::bigint,
  'the upgrade bridge retains a legacy technician identity and membership history'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);
select is((select count(*) from public.organizations where id = '82000000-0000-0000-0000-000000000001'), 1::bigint, 'an active member can read their organization');
select is((select count(*) from public.organization_memberships where organization_id = '82000000-0000-0000-0000-000000000001'), 7::bigint, 'a member with iam.membership.read can list memberships in their organization');
select is((select count(*) from public.organization_memberships where organization_id = '82000000-0000-0000-0000-000000000002'), 0::bigint, 'IAM membership reads do not cross organizations');
select is((select count(*) from public.profiles where id = '83000000-0000-0000-0000-000000000002'), 1::bigint, 'membership.read exposes minimal profile metadata for a shared tenant');
select is((select count(*) from public.profiles where id = '83000000-0000-0000-0000-000000000008'), 0::bigint, 'membership.read does not expose a profile belonging only to another tenant');
select throws_ok(
  $$select auth_user_id from public.profiles where id = '83000000-0000-0000-0000-000000000002'$$,
  '42501', null,
  'profile reads do not expose the auth identity column'
);
select is((select count(*) from public.roles where organization_id = '82000000-0000-0000-0000-000000000001'), 5::bigint, 'role.read exposes roles in its authorized tenant');
select is((select count(*) from public.roles where organization_id = '82000000-0000-0000-0000-000000000002'), 0::bigint, 'role reads do not cross tenants');
select is((select count(*) from public.role_permissions where organization_id = '82000000-0000-0000-0000-000000000001'), 6::bigint, 'role.read exposes composition in its authorized tenant');
select is((select count(*) from public.role_permissions where organization_id = '82000000-0000-0000-0000-000000000002'), 0::bigint, 'role-permission reads do not cross tenants');
select is((select count(*) from public.role_assignments where organization_id = '82000000-0000-0000-0000-000000000001'), 7::bigint, 'role.read exposes assignments in its authorized tenant');
select is((select count(*) from public.role_assignments where organization_id = '82000000-0000-0000-0000-000000000002'), 0::bigint, 'role-assignment reads do not cross tenants');
select ok(public.has_active_iam_permission('82000000-0000-0000-0000-000000000001', 'iam.role.read'), 'an active role assignment grants its permission');
select throws_ok(
  $$insert into public.role_permissions (organization_id, role_id, permission_code) values ('82000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000001', 'clinical.organization.read')$$,
  '42501',
  'permission denied for table role_permissions',
  'an authenticated administrator cannot elevate a role with direct role-permission DML'
);
select throws_ok(
  $$update public.organization_memberships set status = 'active' where id = '84000000-0000-0000-0000-000000000003'$$,
  '42501',
  'permission denied for table organization_memberships',
  'an authenticated administrator cannot change memberships directly'
);
select throws_ok(
  $$insert into public.role_assignments (organization_id, membership_id, role_id) values ('82000000-0000-0000-0000-000000000001', '84000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000001')$$,
  '42501',
  'permission denied for table role_assignments',
  'an authenticated administrator cannot self-assign roles directly'
);
select throws_ok(
  $$update public.roles set description = 'Changed directly' where id = '85000000-0000-0000-0000-000000000001'$$,
  '42501',
  'permission denied for table roles',
  'an authenticated administrator cannot modify roles directly'
);
select throws_ok(
  $$update public.role_assignments set revoked_at = now() where id = '86000000-0000-0000-0000-000000000001'$$,
  '42501',
  'permission denied for table role_assignments',
  'an authenticated administrator cannot revoke a role directly'
);
select throws_ok(
  $$insert into public.permission_catalog (code, family, description) values ('iam.self.elevate', 'iam', 'Must fail.')$$,
  '42501',
  'permission denied for table permission_catalog',
  'an authenticated administrator cannot change the fixed permission catalog'
);
reset role;

create function public.iam_test_protected_role_id()
returns uuid
language sql
security definer
set search_path = ''
as $$
  select id from public.roles
  where protected_kind = 'demo_administrator'
$$;
grant execute on function public.iam_test_protected_role_id() to service_role;
create function public.iam_test_protected_org_id()
returns uuid
language sql
security definer
set search_path = ''
as $$
  select organization_id from public.roles
  where protected_kind = 'demo_administrator'
$$;
grant execute on function public.iam_test_protected_org_id() to service_role;
set local role service_role;
select throws_ok(
  $$insert into public.role_permissions (organization_id, role_id, permission_code) values (public.iam_test_protected_org_id(), public.iam_test_protected_role_id(), 'audit.read')$$,
  '42501', 'permission denied for table role_permissions',
  'service_role cannot add permissions to the protected role'
);
select throws_ok(
  $$update public.role_permissions set permission_code = 'audit.read' where permission_code = 'clinical.organization.read'$$,
  '42501', 'permission denied for table role_permissions',
  'service_role cannot update protected role composition'
);
select throws_ok(
  $$delete from public.role_permissions where permission_code = 'clinical.organization.read'$$,
  '42501', 'permission denied for table role_permissions',
  'service_role cannot delete protected role composition'
);
select throws_ok(
  $$update public.permission_catalog set delegation_policy = 'ordinary' where code = 'clinical.organization.read'$$,
  'P0001', 'permission catalog is migration-managed',
  'service_role cannot downgrade the reserved permission policy'
);
select throws_ok(
  $$update public.permission_catalog set status = 'deprecated', deprecated_at = now() where code = 'clinical.organization.read'$$,
  'P0001', 'permission catalog is migration-managed',
  'service_role cannot change a permission status'
);
select throws_ok(
  $$insert into public.permission_catalog (code, family, description) values ('iam.runtime.injected', 'iam', 'Must fail.')$$,
  'P0001', 'permission catalog is migration-managed',
  'service_role cannot create a permission code'
);
select throws_ok(
  $$delete from public.permission_catalog where code = 'clinical.organization.read'$$,
  'P0001', 'permission catalog is migration-managed',
  'service_role cannot delete a permission code'
);
select throws_ok(
  $$insert into public.role_permissions (organization_id, role_id, permission_code) values ('82000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000001', 'clinical.organization.read')$$,
  '42501', 'permission denied for table role_permissions',
  'service_role cannot complete the catalog-downgrade and permission-injection bypass'
);
reset role;
select is(
  (select delegation_policy from public.permission_catalog where code = 'clinical.organization.read'),
  'system_only',
  'failed service_role catalog DML leaves the reserved policy unchanged'
);

update public.role_assignments set revoked_at = now()
where id = '86000000-0000-0000-0000-000000000007';
select lives_ok(
  $$insert into public.role_assignments (organization_id, membership_id, role_id, created_by_membership_id)
    values ('82000000-0000-0000-0000-000000000001', '84000000-0000-0000-0000-000000000007', '85000000-0000-0000-0000-000000000005', '84000000-0000-0000-0000-000000000001')$$,
  'a new equivalent role grant can follow a revoked historical grant'
);
select throws_ok(
  $$insert into public.role_assignments (organization_id, membership_id, role_id, valid_from, created_by_membership_id)
    values ('82000000-0000-0000-0000-000000000001', '84000000-0000-0000-0000-000000000007', '85000000-0000-0000-0000-000000000005', now(), '84000000-0000-0000-0000-000000000001')$$,
  '23P01', null,
  'overlapping effective equivalent grants are rejected'
);
select throws_ok(
  $$insert into public.role_assignments (organization_id, membership_id, role_id)
    values ('82000000-0000-0000-0000-000000000001', '84000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000002')$$,
  '23514', 'new role assignments require an active organization, profile, membership, and role',
  'new grants to an inactive role are rejected'
);
select throws_ok(
  $$insert into public.role_assignments (organization_id, membership_id, role_id)
    values ('82000000-0000-0000-0000-000000000001', '84000000-0000-0000-0000-000000000002', '85000000-0000-0000-0000-000000000001')$$,
  '23514', 'new role assignments require an active organization, profile, membership, and role',
  'a suspended profile cannot receive a new role assignment even with an active membership'
);
select throws_ok(
  $$insert into public.role_permissions (organization_id, role_id, permission_code)
    values ('82000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000002', 'audit.read')$$,
  '23514', 'permissions cannot be granted to an inactive role',
  'new permission grants to an inactive role are rejected'
);
update public.permission_catalog set status = 'deprecated', deprecated_at = now()
where code = 'audit.read';
select throws_ok(
  $$insert into public.role_permissions (organization_id, role_id, permission_code)
    values ('82000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000001', 'audit.read')$$,
  '23514', 'deprecated permissions cannot be newly granted',
  'new grants of deprecated permissions are rejected'
);
update public.permission_catalog set status = 'active', deprecated_at = null
where code = 'audit.read';

update public.organizations set status = 'suspended'
where id = '82000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);
select ok(not public.has_active_organization_membership('82000000-0000-0000-0000-000000000001'), 'suspended organizations have no active membership authority');
select ok(not public.has_active_iam_permission('82000000-0000-0000-0000-000000000001', 'iam.role.read'), 'suspended organizations deny effective IAM permissions');
select is((select count(*) from public.organizations where id = '82000000-0000-0000-0000-000000000001'), 0::bigint, 'organization RLS denies suspended organization reads');
select is((select count(*) from public.roles where organization_id = '82000000-0000-0000-0000-000000000001'), 0::bigint, 'role RLS denies reads in a suspended organization');
reset role;
update public.organizations set status = 'active'
where id = '82000000-0000-0000-0000-000000000001';

select throws_ok(
  $$update public.organizations set timezone = 'Mars/Olympus' where slug = 'demo-hospital'$$,
  '23514', 'timezone must be a valid IANA timezone name',
  'organization timezone must be a valid IANA name'
);

select is(
  (select count(*) from public.role_permissions permission
   join public.roles role on role.id = permission.role_id
   where permission.permission_code = 'clinical.organization.read'
     and role.protected_kind = 'demo_administrator'),
  1::bigint,
  'the reserved permission belongs only to the protected seed role'
);
select throws_ok(
  $$insert into public.role_permissions (organization_id, role_id, permission_code) values ('82000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000001', 'clinical.organization.read')$$,
  'P0001',
  'system-only permissions require the protected demo administrator role',
  'the reserved permission cannot be copied to an ordinary role'
);
select throws_ok(
  $$update public.roles set status = 'inactive' where protected_kind = 'demo_administrator'$$,
  'P0001',
  'protected roles are immutable outside a dedicated server operation',
  'the protected seed role cannot be disabled directly'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000002', true);
select ok(not public.has_active_iam_permission('82000000-0000-0000-0000-000000000001', 'iam.role.read'), 'a suspended profile has no effective permissions');
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000003', true);
select ok(not public.has_active_iam_permission('82000000-0000-0000-0000-000000000001', 'iam.role.read'), 'a suspended membership has no effective permissions');
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000004', true);
select ok(not public.has_active_iam_permission('82000000-0000-0000-0000-000000000001', 'iam.role.read'), 'an inactive role has no effective permissions');
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000005', true);
select ok(not public.has_active_iam_permission('82000000-0000-0000-0000-000000000001', 'iam.role.read'), 'a future role assignment has no effective permissions');
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000006', true);
select ok(not public.has_active_iam_permission('82000000-0000-0000-0000-000000000001', 'iam.role.read'), 'an expired role assignment has no effective permissions');
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000007', true);
select ok(public.has_active_iam_permission('82000000-0000-0000-0000-000000000001', 'iam.role.read'), 'an unrevoked current role assignment has its permission');
reset role;
select lives_ok(
  $$insert into public.role_assignments (organization_id, membership_id, role_id, created_by_membership_id)
    values ('82000000-0000-0000-0000-000000000001', '84000000-0000-0000-0000-000000000006', '85000000-0000-0000-0000-000000000004', '84000000-0000-0000-0000-000000000001')$$,
  'a new equivalent role grant can follow an expired historical grant'
);
select is(
  (select count(*) from public.role_assignments
   where membership_id = '84000000-0000-0000-0000-000000000006'
     and role_id = '85000000-0000-0000-0000-000000000004'),
  2::bigint,
  'the expired assignment and its replacement both remain in history'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000006', true);
select ok(public.has_active_iam_permission('82000000-0000-0000-0000-000000000001', 'iam.role.read'), 'the replacement grant is effective after an expired grant');
reset role;
update public.role_assignments
set revoked_at = now()
where membership_id = '84000000-0000-0000-0000-000000000007'
  and role_id = '85000000-0000-0000-0000-000000000005'
  and revoked_at is null;
set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000007', true);
select ok(not public.has_active_iam_permission('82000000-0000-0000-0000-000000000001', 'iam.role.read'), 'a revoked role assignment loses its permission immediately');
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000008', true);
select ok(not public.has_active_iam_permission('82000000-0000-0000-0000-000000000001', 'iam.role.read'), 'a role assignment in another organization is not effective in organization A');
reset role;

select is(
  (select count(*) from public.roles role
   join public.organizations organization on organization.id = role.organization_id
   where organization.slug = 'demo-hospital'
     and role.name in ('Administrador protegido', 'Personal clínico')),
  2::bigint,
  'migration seeds exactly the two demo roles without relying on supabase/seed.sql'
);
select is(
  (select delegation_policy from public.permission_catalog where code = 'clinical.organization.read'),
  'system_only',
  'clinical.organization.read is marked system_only in the fixed catalog'
);

select * from finish();
rollback;
