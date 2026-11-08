begin;
create extension if not exists pgtap;

select plan(5);

select ok(coalesce((
  select bool_and(coalesce(proconfig @> array['search_path=""'], false))
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private') and p.prosecdef
), true), 'every public/private SECURITY DEFINER function fixes an empty search_path');

select ok(exists (
  select 1 from pg_trigger
  where tgrelid = 'public.audit_events'::regclass
    and tgname = 'audit_events_append_only' and not tgisinternal
), 'audit events have the append-only trigger');

select ok(
  has_function_privilege('authenticated', 'public.grant_care_assignment(uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.revoke_care_assignment(uuid,uuid,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.grant_care_assignment(uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.revoke_care_assignment(uuid,uuid,uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.grant_care_assignment(uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.revoke_care_assignment(uuid,uuid,uuid)', 'execute'),
  'assignment RPCs are executable only by authenticated');

select ok((
  select count(*) = 8 from pg_index i
  join pg_class t on t.oid = i.indrelid
  join pg_namespace tn on tn.oid = t.relnamespace
  join pg_class x on x.oid = i.indexrelid
  join pg_namespace xn on xn.oid = x.relnamespace
  where tn.nspname = 'public' and xn.nspname = 'public'
    and (t.relname, x.relname) in (
      ('hospitalizations', 'hospitalizations_pkey'),
      ('organization_memberships', 'organization_memberships_pkey'),
      ('role_assignments', 'role_assignments_effective_membership_idx'),
      ('role_permissions', 'role_permissions_pkey'),
      ('care_assignments', 'care_assignments_episode_idx'),
      ('care_assignments', 'care_assignments_membership_validity_idx'),
      ('clinical_events', 'clinical_events_episode_timeline_idx'),
      ('profiles', 'profiles_auth_user_id_key')
    )
), 'the eight expected public-schema authorization and timeline indexes exist');

select ok(not exists (
  select 1 from pg_policies
  where schemaname = 'public'
    and tablename in ('patients', 'clinical_events')
    and coalesce(qual, '') || ' ' || coalesce(with_check, '') ilike any(array[
      '%practitioner_role%', '%technician%', '%physician%', '%nurse%', '%administrator%'
    ])
), 'clinical policies do not authorize by role enum or role name');

select * from finish();
rollback;
