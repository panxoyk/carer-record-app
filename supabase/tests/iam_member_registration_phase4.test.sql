begin;
create extension if not exists pgtap;
select plan(30);
select public.bootstrap_synthetic_hospitalization_fixtures();
insert into auth.users(id,email) values
  ('77777777-7777-4777-8777-777777777777','member@example.test'),
  ('77777777-7777-4777-8777-777777777778','other@example.test');
insert into public.roles(organization_id,name,description,is_system,protected_kind)
select id,'Phase 4.2 registration role','Synthetic ordinary role',false,null
from public.organizations where slug='demo-hospital';
create function public.phase42_registration_role() returns uuid language sql security definer set search_path='' as $$
  select id from public.roles where name='Phase 4.2 registration role'
$$;
grant execute on function public.phase42_registration_role() to authenticated;

select ok(has_function_privilege('authenticated','public.register_organization_member(uuid,uuid,text,text,uuid,uuid)','execute'), 'authenticated may invoke member registration');
select ok(not has_function_privilege('service_role','public.register_organization_member(uuid,uuid,text,text,uuid,uuid)','execute'), 'service role cannot invoke registration RPC');
select ok(has_function_privilege('authenticated','public.preflight_organization_member_registration(uuid,text,text,uuid,uuid)','execute'), 'authenticated may invoke preflight');
select ok(not has_table_privilege('authenticated','public.profiles','insert') and not has_table_privilege('service_role','public.profiles','insert'), 'runtime roles lack direct profile insert');

set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-3333-3333-333333333333',true);
select is((select result_code from public.preflight_organization_member_registration(
  (select id from public.organizations where slug='demo-hospital'),'member@example.test','Synthetic Member',
  public.phase42_registration_role(),'c9100000-0000-4000-8000-000000000001')),'ready','authorized actor preflights new member');
select is((select result_code from public.preflight_organization_member_registration(
  (select id from public.organizations where slug='demo-hospital'),'clinical@example.test','Synthetic Clinician',
  (select id from public.roles where name='Personal clínico'),'c9100000-0000-4000-8000-000000000006')),'ready','active system-marked ordinary role follows the phase 4.1 delegation rule');
select is((select result_code from public.register_organization_member(
  (select id from public.organizations where slug='demo-hospital'),'77777777-7777-4777-8777-777777777777',
  'member@example.test','Synthetic Member',public.phase42_registration_role(),
  'c9100000-0000-4000-8000-000000000001')),'registered','profile, membership and role assignment register transactionally');
select ok((select replayed from public.preflight_organization_member_registration(
  (select id from public.organizations where slug='demo-hospital'),'MEMBER@example.test','Synthetic Member',
  public.phase42_registration_role(),'c9100000-0000-4000-8000-000000000001')),'preflight replays completed request before Auth user creation');
select is((select result_code from public.preflight_organization_member_registration(
  (select id from public.organizations where slug='demo-hospital'),'different@example.test','Synthetic Member',
  public.phase42_registration_role(),'c9100000-0000-4000-8000-000000000001')),'idempotency_conflict','same idempotency key with different logical payload conflicts');
select is((select result_code from public.register_organization_member(
  (select id from public.organizations where slug='demo-hospital'),'77777777-7777-4777-8777-777777777777',
  'member@example.test','Synthetic Member',public.phase42_registration_role(),
  'c9100000-0000-4000-8000-000000000001')),'registered','DB registration replays without duplicate rows');
reset role;
select is((select count(*)::int from public.profiles where auth_user_id='77777777-7777-4777-8777-777777777777'),1,'replay does not duplicate profile');
select is((select count(*)::int from public.organization_memberships m join public.profiles p on p.id=m.profile_id where p.auth_user_id='77777777-7777-4777-8777-777777777777'),1,'replay does not duplicate membership');
select is((select count(*)::int from public.role_assignments ra join public.organization_memberships m on m.id=ra.membership_id join public.profiles p on p.id=m.profile_id where p.auth_user_id='77777777-7777-4777-8777-777777777777'),1,'replay does not duplicate role assignment');
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-3333-3333-333333333333',true);
select is((select result_code from public.register_organization_member(
  (select id from public.organizations where slug='demo-hospital'),'33333333-3333-3333-3333-333333333333',
  'self@example.test','Self',public.phase42_registration_role(),
  'c9100000-0000-4000-8000-000000000002')),'invalid_request','actor cannot register itself');
select is((select result_code from public.register_organization_member(
  (select id from public.organizations where slug='demo-hospital'),'88888888-8888-4888-8888-888888888888',
  'missing@example.test','Missing',public.phase42_registration_role(),
  'c9100000-0000-4000-8000-000000000003')),'invalid_request','Auth identity must exist');
select is((select result_code from public.register_organization_member(
  (select id from public.organizations where slug='demo-hospital'),'77777777-7777-4777-8777-777777777778',
  'member@example.test','Email mismatch',public.phase42_registration_role(),
  'c9100000-0000-4000-8000-000000000007')),'invalid_request','Auth email mismatch is denied');
select is((select result_code from public.register_organization_member(
  (select id from public.organizations where slug='demo-hospital'),'77777777-7777-4777-8777-777777777778',
  null,'Null email',public.phase42_registration_role(),
  'c9100000-0000-4000-8000-000000000008')),'invalid_request','null request email is denied');
select ok((select count(*)=2 from public.audit_events where action='iam.member.register'
  and idempotency_key in ('c9100000-0000-4000-8000-000000000007','c9100000-0000-4000-8000-000000000008')
  and result='denied' and metadata->>'result_code'='invalid_request'),'email denials are audited');
reset role;
select ok(not exists(select 1 from public.profiles where auth_user_id='77777777-7777-4777-8777-777777777778')
  and not exists(select 1 from public.organization_memberships m join public.profiles p on p.id=m.profile_id where p.auth_user_id='77777777-7777-4777-8777-777777777778')
  and not exists(select 1 from public.role_assignments ra join public.organization_memberships m on m.id=ra.membership_id join public.profiles p on p.id=m.profile_id where p.auth_user_id='77777777-7777-4777-8777-777777777778'),
  'email mismatch and null-email requests create no institutional rows');
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-3333-3333-333333333333',true);
select is((select result_code from public.register_organization_member(
  (select id from public.organizations where slug='demo-hospital'),'77777777-7777-4777-8777-777777777777',
  'member@example.test','Protected',(select id from public.roles where protected_kind='demo_administrator'),
  'c9100000-0000-4000-8000-000000000004')),'role_not_delegable','protected role cannot be assigned through registration');
select is((select result_code from public.register_organization_member(
  '00000000-0000-0000-0000-000000000000','77777777-7777-4777-8777-777777777777',
  'other@example.test','Other',public.phase42_registration_role(),
  'c9100000-0000-4000-8000-000000000005')),'denied','other tenant is denied');
reset role;
delete from public.role_permissions rp using public.roles r
 where rp.role_id=r.id and r.protected_kind='demo_administrator' and rp.permission_code='iam.membership.manage';
set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-3333-3333-333333333333',true);
select is((select result_code from public.preflight_organization_member_registration(
  (select id from public.organizations where slug='demo-hospital'),'member@example.test','Synthetic Member',
  public.phase42_registration_role(),'c9100000-0000-4000-8000-000000000001')),'denied','authority is revalidated before replay is revealed');
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select is((select result_code from public.preflight_organization_member_registration(
  (select id from public.organizations where slug='demo-hospital'),'denied@example.test','Synthetic Denied',
  public.phase42_registration_role(),'c9100000-0000-4000-8000-000000000009')),'denied','resolvable actor without permissions is denied');
reset role;
select is((select count(*)::int from public.audit_events where action='iam.member.register'
  and idempotency_key='c9100000-0000-4000-8000-000000000009' and result='denied'),1,'first resolvable permission denial is audited once');
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select is((select result_code from public.preflight_organization_member_registration(
  (select id from public.organizations where slug='demo-hospital'),'denied@example.test','Synthetic Denied',
  public.phase42_registration_role(),'c9100000-0000-4000-8000-000000000009')),'denied','same unauthorized retry returns stable denial');
select is((select result_code from public.preflight_organization_member_registration(
  (select id from public.organizations where slug='demo-hospital'),'different@example.test','Synthetic Denied',
  public.phase42_registration_role(),'c9100000-0000-4000-8000-000000000009')),'denied','unauthorized caller cannot learn payload conflict');
reset role;
insert into public.role_permissions(organization_id,role_id,permission_code)
select r.organization_id,r.id,p.code from public.roles r
cross join public.permission_catalog p
where r.name='Personal clínico' and p.code in ('iam.membership.manage','iam.role.assign')
on conflict do nothing;
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
select is((select result_code from public.preflight_organization_member_registration(
  (select id from public.organizations where slug='demo-hospital'),'different@example.test','Synthetic Denied',
  public.phase42_registration_role(),'c9100000-0000-4000-8000-000000000009')),'idempotency_conflict','authorized actor can detect payload conflict after authority returns');
select throws_ok($$insert into public.profiles(auth_user_id,display_name) values ('99999999-9999-4999-8999-999999999999','Synthetic')$$,'42501',null,'authenticated direct profile DML guard rejects writes');
reset role;
set local role service_role;
select throws_ok($$insert into public.profiles(auth_user_id,display_name) values ('99999999-9999-4999-8999-999999999999','Synthetic')$$,'42501',null,'service_role direct profile DML guard rejects writes');
reset role;
select ok((select count(*)=0 from public.audit_events where action='iam.member.register' and metadata::text ~* '(member@example|Synthetic Member|password|email)'), 'registration audit stores no raw email, display name or password');
select * from finish();
rollback;
