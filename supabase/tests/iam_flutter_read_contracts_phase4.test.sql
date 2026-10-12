begin;
create extension if not exists pgtap;
select plan(30);

select public.bootstrap_synthetic_hospitalization_fixtures();
insert into public.organizations (id, slug, display_name)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'contract-other-tenant', 'Other synthetic tenant');
insert into public.roles (id, organization_id, name, description)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeef',
  'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'Other tenant role', 'Synthetic isolation fixture');
set local role authenticated;
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);

select ok((select count(*) > 0 from public.iam_current_context
  where organization_id = (select id from public.organizations where slug='demo-hospital')),
  'current IAM context is derived for the authenticated identity');
select ok(not has_column_privilege('authenticated','public.profiles','auth_user_id','select'),
  'directory contracts do not require exposing auth_user_id');
select ok(not exists(select 1 from information_schema.columns
  where table_schema='public' and table_name in ('iam_current_context','iam_member_directory',
    'iam_role_directory','iam_member_role_assignments','iam_assignment_hospitalizations',
    'iam_assignment_eligible_members') and column_name in ('auth_user_id','email','rut','payload')),
  'administrative read contracts exclude identity contact and clinical payload columns');
select is((select count(*)::int from public.iam_member_directory
  where organization_id=(select id from public.organizations where slug='demo-hospital')),
  (select count(*)::int from public.organization_memberships
    where organization_id=(select id from public.organizations where slug='demo-hospital')),
  'membership directory includes tenant membership states while remaining tenant-scoped');
select ok((select count(*) > 0 from public.iam_role_directory
  where organization_id=(select id from public.organizations where slug='demo-hospital')
    and protected_kind is null and role_status='active'),
  'role directory contains active ordinary roles');
select is((select count(*)::int from public.iam_assignment_eligible_members
  where organization_id=(select id from public.organizations where slug='demo-hospital')
    and membership_id=(select id from public.organization_memberships
      where profile_id=public.iam_current_profile_id())),
  0, 'care-assignment target directory hides the current actor');
select ok((select count(*) > 0 from public.iam_assignment_hospitalizations
  where organization_id=(select id from public.organizations where slug='demo-hospital')),
  'assignment administration exposes only permitted hospitalization identifiers and state');
select is((select count(*)::int from public.iam_role_directory where protected_kind is not null),
  0, 'protected and catalog roles are never present in the role directory');
select is((select count(*)::int from public.iam_member_role_assignments where protected_kind is not null),
  0, 'protected role assignments are never present in the assignment directory');
select ok(not exists(select 1 from pg_policies where schemaname='public' and tablename='profiles'
  and policyname='authorized members read tenant profiles'),
  'the redundant profile policy from the original Flutter contract is removed');
select ok(not has_table_privilege('anon','public.iam_current_context','select')
  and not has_table_privilege('anon','public.iam_role_directory','select'),
  'anonymous callers have no direct read grant to IAM contracts');
select ok(not exists(select 1 from public.iam_current_context
    where organization_id='eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')
  and not exists(select 1 from public.iam_member_directory
    where organization_id='eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')
  and not exists(select 1 from public.iam_role_directory
    where organization_id='eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')
  and not exists(select 1 from public.iam_member_role_assignments
    where organization_id='eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')
  and not exists(select 1 from public.iam_assignment_hospitalizations
    where organization_id='eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')
  and not exists(select 1 from public.iam_assignment_eligible_members
    where organization_id='eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'),
  'all IAM read contracts deny cross-tenant rows');
reset role;
select set_config('cra.contract.admin_role', (select id::text from public.roles
  where organization_id=(select id from public.organizations where slug='demo-hospital')
    and protected_kind='demo_administrator'), true);
select set_config('cra.contract.partial_actor_role', (select r.id::text
  from public.roles r
  join public.role_assignments ra on ra.role_id=r.id and ra.organization_id=r.organization_id
  join public.organization_memberships m on m.id=ra.membership_id and m.organization_id=ra.organization_id
  join public.profiles p on p.id=m.profile_id
  where p.auth_user_id='11111111-1111-1111-1111-111111111111'
    and r.protected_kind is null and r.status='active' and ra.revoked_at is null
  order by ra.id limit 1), true);
insert into public.role_permissions (organization_id, role_id, permission_code)
select organization_id, id, 'iam.membership.read' from public.roles
where id=current_setting('cra.contract.partial_actor_role')::uuid
on conflict (organization_id, role_id, permission_code) do nothing;
set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
select ok(public.has_active_iam_permission(
    (select id from public.organizations where slug='demo-hospital'), 'iam.membership.read')
  and not public.has_active_iam_permission(
    (select id from public.organizations where slug='demo-hospital'), 'clinical.assignment.manage')
  and not public.has_active_iam_permission(
    (select id from public.organizations where slug='demo-hospital'), 'iam.role.read'),
  'synthetic active actor has membership/assignment authority but not iam.role.read');
select ok(exists(select 1 from public.roles where protected_kind is null)
  and not exists(select 1 from public.roles where protected_kind is not null),
  'auxiliary role policy exposes ordinary roles and withholds protected roles');
select ok(exists(select 1 from public.role_permissions rp join public.roles r
    on r.organization_id=rp.organization_id and r.id=rp.role_id where r.protected_kind is null)
  and not exists(select 1 from public.role_permissions
    where role_id=current_setting('cra.contract.admin_role')::uuid),
  'auxiliary composition policy exposes ordinary permissions and withholds protected composition');
select ok(exists(select 1 from public.role_assignments ra join public.roles r
    on r.organization_id=ra.organization_id and r.id=ra.role_id where r.protected_kind is null)
  and not exists(select 1 from public.role_assignments
    where role_id=current_setting('cra.contract.admin_role')::uuid),
  'auxiliary history policy exposes ordinary grants and withholds protected assignments');
select ok(exists(select 1 from public.iam_member_role_assignments where protected_kind is null)
  and not exists(select 1 from public.iam_member_role_assignments where protected_kind is not null),
  'the typed role-assignment history view remains ordinary-only');
select ok(not exists(select 1 from public.roles where organization_id='eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')
  and not exists(select 1 from public.role_permissions where organization_id='eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')
  and not exists(select 1 from public.role_assignments where organization_id='eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'),
  'auxiliary policies deny direct base-table rows from another tenant');
reset role;
delete from public.role_permissions
where role_id=current_setting('cra.contract.partial_actor_role')::uuid
  and permission_code='iam.membership.read';
set local role authenticated;
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
select ok(public.has_active_iam_permission(
    (select id from public.organizations where slug='demo-hospital'), 'iam.role.read')
  and exists(select 1 from public.roles where protected_kind is not null)
  and exists(select 1 from public.role_permissions rp join public.roles r
    on r.organization_id=rp.organization_id and r.id=rp.role_id where r.protected_kind is not null)
  and exists(select 1 from public.role_permissions
    where role_id=current_setting('cra.contract.admin_role')::uuid)
  and exists(select 1 from public.role_assignments ra join public.roles r
    on r.organization_id=ra.organization_id and r.id=ra.role_id where r.protected_kind is not null)
  and exists(select 1 from public.role_assignments
    where role_id=current_setting('cra.contract.admin_role')::uuid),
  'Admin retains the pre-existing iam.role.read access to protected base rows');
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
select ok(
  (select array_agg(attname::text order by attnum) from pg_attribute where attrelid='public.iam_current_context'::regclass and attnum>0 and not attisdropped)
    = array['organization_id','organization_name','profile_id','display_name','profile_status','membership_id','membership_status','permission_code']::text[]
  and (select array_agg(attname::text order by attnum) from pg_attribute where attrelid='public.iam_member_directory'::regclass and attnum>0 and not attisdropped)
    = array['organization_id','membership_id','profile_id','display_name','profile_status','membership_status','valid_from','valid_until']::text[]
  and (select array_agg(attname::text order by attnum) from pg_attribute where attrelid='public.iam_role_directory'::regclass and attnum>0 and not attisdropped)
    = array['organization_id','role_id','role_name','description','role_status','protected_kind','permission_code']::text[]
  and (select array_agg(attname::text order by attnum) from pg_attribute where attrelid='public.iam_member_role_assignments'::regclass and attnum>0 and not attisdropped)
    = array['organization_id','assignment_id','membership_id','role_id','role_name','protected_kind','valid_from','valid_until','revoked_at']::text[]
  and (select array_agg(attname::text order by attnum) from pg_attribute where attrelid='public.iam_assignment_hospitalizations'::regclass and attnum>0 and not attisdropped)
    = array['organization_id','hospitalization_id','hospitalization_status','admitted_at','discharged_at','assignment_id','membership_id','assignment_valid_from','assignment_valid_until','revoked_at']::text[]
  and (select array_agg(attname::text order by attnum) from pg_attribute where attrelid='public.iam_assignment_eligible_members'::regclass and attnum>0 and not attisdropped)
    = array['organization_id','membership_id','display_name']::text[],
  'all six Flutter views expose only their exact typed column contracts');
select ok((select bool_and(reloptions @> array['security_invoker=true','security_barrier=true'])
  from pg_class where oid = any(array[
    'public.iam_current_context'::regclass, 'public.iam_member_directory'::regclass,
    'public.iam_role_directory'::regclass, 'public.iam_member_role_assignments'::regclass,
    'public.iam_assignment_hospitalizations'::regclass,
    'public.iam_assignment_eligible_members'::regclass])),
  'all Flutter read views use security_invoker and security_barrier');

reset role;
select set_config('cra.contract.target_membership', (select m.id::text
  from public.organization_memberships m
  join public.profiles p on p.id=m.profile_id
  where m.organization_id=(select id from public.organizations where slug='demo-hospital')
    and p.auth_user_id <> '33333333-3333-3333-3333-333333333333'
    and exists(select 1 from public.role_assignments ra where ra.membership_id=m.id)
    and exists(select 1 from public.care_assignments ca where ca.membership_id=m.id)
  order by m.id limit 1), true);
update public.profiles set status='suspended'
where id=(select profile_id from public.organization_memberships
  where id=current_setting('cra.contract.target_membership')::uuid);
set local role authenticated;
select ok(exists(select 1 from public.iam_member_directory
    where membership_id=current_setting('cra.contract.target_membership')::uuid
      and profile_status='suspended')
  and (select count(*) from public.iam_member_role_assignments
    where membership_id=current_setting('cra.contract.target_membership')::uuid) > 0
  and not exists(select 1 from public.iam_assignment_eligible_members
    where membership_id=current_setting('cra.contract.target_membership')::uuid)
  and (select count(*) from public.iam_assignment_hospitalizations
    where membership_id=current_setting('cra.contract.target_membership')::uuid
      and assignment_id is not null) > 0,
  'a suspended target profile remains visible with role/care history but is not eligible for new care assignments');
reset role;
update public.profiles set status='active'
where id=(select profile_id from public.organization_memberships
  where id=current_setting('cra.contract.target_membership')::uuid);
update public.organization_memberships set status='suspended'
where id=current_setting('cra.contract.target_membership')::uuid;
set local role authenticated;
select ok(exists(select 1 from public.iam_member_directory
    where membership_id=current_setting('cra.contract.target_membership')::uuid
      and membership_status='suspended')
  and (select count(*) from public.iam_member_role_assignments
    where membership_id=current_setting('cra.contract.target_membership')::uuid) > 0
  and not exists(select 1 from public.iam_assignment_eligible_members
    where membership_id=current_setting('cra.contract.target_membership')::uuid)
  and (select count(*) from public.iam_assignment_hospitalizations
    where membership_id=current_setting('cra.contract.target_membership')::uuid
      and assignment_id is not null) > 0,
  'a suspended target membership remains visible with role/care history but is not eligible for new care assignments');
reset role;
update public.organization_memberships set status='active'
where id=current_setting('cra.contract.target_membership')::uuid;

reset role;
update public.organizations set status='suspended' where slug='demo-hospital';
set local role authenticated;
select ok(not exists(select 1 from public.iam_current_context)
  and not exists(select 1 from public.iam_member_directory)
  and not exists(select 1 from public.iam_role_directory)
  and not exists(select 1 from public.iam_member_role_assignments)
  and not exists(select 1 from public.iam_assignment_hospitalizations)
  and not exists(select 1 from public.iam_assignment_eligible_members),
  'a suspended actor organization contributes no IAM contract rows');
reset role;
update public.organizations set status='active' where slug='demo-hospital';
update public.profiles set status='suspended'
where auth_user_id='33333333-3333-3333-3333-333333333333';
set local role authenticated;
select ok(not exists(select 1 from public.iam_current_context)
  and not exists(select 1 from public.iam_member_directory)
  and not exists(select 1 from public.iam_role_directory)
  and not exists(select 1 from public.iam_member_role_assignments)
  and not exists(select 1 from public.iam_assignment_hospitalizations)
  and not exists(select 1 from public.iam_assignment_eligible_members),
  'a suspended actor profile cannot read any IAM contract');
reset role;
update public.profiles set status='active'
where auth_user_id='33333333-3333-3333-3333-333333333333';
update public.organization_memberships set status='suspended'
where profile_id=(select id from public.profiles where auth_user_id='33333333-3333-3333-3333-333333333333')
  and organization_id=(select id from public.organizations where slug='demo-hospital');
set local role authenticated;
select is((select count(*)::int from public.iam_current_context), 0,
  'a suspended membership contributes no IAM context');
reset role;
update public.organization_memberships set status='active'
where profile_id=(select id from public.profiles where auth_user_id='33333333-3333-3333-3333-333333333333')
  and organization_id=(select id from public.organizations where slug='demo-hospital');

select set_config('cra.contract.inactive_role', (select id::text from public.roles
  where organization_id=(select id from public.organizations where slug='demo-hospital')
    and protected_kind is null and status='active' order by name limit 1), true);
reset role;
update public.roles set status='inactive' where id=current_setting('cra.contract.inactive_role')::uuid;
set local role authenticated;
select is((select count(*)::int from public.iam_role_directory
    where role_id=current_setting('cra.contract.inactive_role')::uuid)
  , 0,
  'inactive ordinary roles are excluded from the role directory');
select ok((select count(*) from public.iam_member_role_assignments
  where role_id=current_setting('cra.contract.inactive_role')::uuid) > 0,
  'historical assignments to inactive ordinary roles remain inspectable');
reset role;
update public.roles set status='active' where id=current_setting('cra.contract.inactive_role')::uuid;

delete from public.role_permissions rp
using public.roles r, public.organizations o
where rp.role_id=r.id and r.organization_id=o.id and o.slug='demo-hospital'
  and r.protected_kind='demo_administrator' and rp.permission_code='clinical.assignment.manage';
set local role authenticated;
select ok(not exists(select 1 from public.iam_current_context where permission_code='clinical.assignment.manage')
  and not exists(select 1 from public.iam_assignment_hospitalizations),
  'revoking an effective permission in-session removes that permission and its administrative view rows');
reset role;
set local role anon;
select throws_ok($$select * from public.iam_current_context$$, '42501',
  'permission denied for view iam_current_context', 'anonymous cannot select IAM context rows');

select * from finish();
rollback;
