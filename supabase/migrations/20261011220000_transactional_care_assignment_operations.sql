-- Phase 2.2: authenticated, audited, idempotent assignment administration.
create table public.audit_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  occurred_at timestamptz not null default now(),
  actor_auth_user_id uuid,
  actor_membership_id uuid,
  action text not null,
  target_type text not null,
  target_id uuid,
  result text not null check (result in ('allowed', 'denied')),
  idempotency_key uuid not null,
  metadata jsonb not null default '{}'::jsonb,
  constraint audit_events_actor_membership_fk foreign key (organization_id, actor_membership_id)
    references public.organization_memberships(organization_id, id) on delete restrict,
  constraint audit_events_metadata_object check (jsonb_typeof(metadata) = 'object'),
  constraint audit_events_action check (action in ('care_assignment.grant', 'care_assignment.revoke')),
  constraint audit_events_target_type check (target_type = 'care_assignment')
);
create unique index audit_events_idempotency_key_idx
  on public.audit_events (organization_id, actor_auth_user_id, action, idempotency_key);
create index audit_events_organization_time_idx on public.audit_events (organization_id, occurred_at desc);
alter table public.audit_events enable row level security;
create policy "audit readers see tenant events" on public.audit_events for select to authenticated
  using (public.has_active_iam_permission(organization_id, 'audit.read'));
revoke all on public.audit_events from public, anon, authenticated, service_role;
grant select on public.audit_events to authenticated;

-- Only the migration owner and the operation functions (owned by postgres) may write.
create or replace function private.protect_care_assignment_runtime_dml()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user <> 'postgres' then
    raise exception 'care assignments are writable only through controlled database operations'
      using errcode = '42501';
  end if;
  return coalesce(new, old);
end;
$$;
create trigger care_assignments_runtime_dml_guard
  before insert or update or delete on public.care_assignments
  for each row execute function private.protect_care_assignment_runtime_dml();

create or replace function private.protect_audit_event_dml()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user <> 'postgres' or tg_op <> 'INSERT' then
    raise exception 'audit events are append-only and operation-managed'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger audit_events_append_only
  before insert or update or delete on public.audit_events
  for each row execute function private.protect_audit_event_dml();
revoke all on function private.protect_care_assignment_runtime_dml() from public, anon, authenticated, service_role;
revoke all on function private.protect_audit_event_dml() from public, anon, authenticated, service_role;

-- The protected demo administrator receives audit.read only via this migration.
insert into public.role_permissions (organization_id, role_id, permission_code)
select role.organization_id, role.id, 'audit.read'
from public.roles role
where role.protected_kind = 'demo_administrator'
on conflict do nothing;

create or replace function private.care_assignment_operation(
  p_action text,
  p_organization_id uuid,
  p_hospitalization_id uuid,
  p_membership_id uuid,
  p_valid_from timestamptz,
  p_valid_until timestamptz,
  p_assignment_id uuid,
  p_idempotency_key uuid
)
returns table (result boolean, assignment_id uuid, result_code text, replayed boolean)
language plpgsql security definer set search_path = '' as $$
declare
  actor_auth uuid := auth.uid();
  actor_membership uuid;
  prior public.audit_events%rowtype;
  signature jsonb;
  new_assignment uuid;
  outcome text;
  success boolean := false;
begin
  if p_organization_id is null or p_idempotency_key is null then
    return query select false, null::uuid, 'invalid_request'::text, false;
    return;
  end if;
  -- Serialize all attempts using this tenant/actor/operation/key, including absent audit rows.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_organization_id::text || ':' || coalesce(actor_auth::text, '') || ':' || p_action || ':' || p_idempotency_key::text, 0));

  select membership.id into actor_membership
  from public.profiles profile
  join public.organization_memberships membership on membership.profile_id = profile.id
  where profile.auth_user_id = actor_auth and profile.status = 'active'
    and membership.organization_id = p_organization_id and membership.status = 'active'
    and membership.valid_from <= pg_catalog.now()
    and (membership.valid_until is null or membership.valid_until > pg_catalog.now());
  -- No resolvable actor: deny without revealing whether the tenant/resource exists.
  if actor_membership is null then
    return query select false, null::uuid, 'denied'::text, false;
    return;
  end if;

  signature := pg_catalog.jsonb_build_object(
    'hospitalization_id', p_hospitalization_id,
    'membership_id', p_membership_id,
    'valid_from', p_valid_from,
    'valid_until', p_valid_until,
    'assignment_id', p_assignment_id
  );
  select * into prior from public.audit_events event
  where event.organization_id = p_organization_id
    and event.actor_auth_user_id = actor_auth and event.action = p_action
    and event.idempotency_key = p_idempotency_key;
  if found then
    if prior.metadata->'request' is distinct from signature then
      return query select false, null::uuid, 'idempotency_conflict'::text, false;
    else
      return query select prior.result = 'allowed', prior.target_id,
        coalesce(prior.metadata->>'result_code', 'denied')::text, true;
    end if;
    return;
  end if;

  if not exists (
    select 1 from public.organizations organization
    where organization.id = p_organization_id and organization.status = 'active'
  ) or not public.has_active_iam_permission(p_organization_id, 'clinical.assignment.manage') then
    outcome := 'denied';
  elsif p_action = 'care_assignment.grant' then
    if p_hospitalization_id is null or p_membership_id is null or p_valid_from is null
       or p_assignment_id is not null or p_valid_until is not null and p_valid_until <= p_valid_from then
      outcome := 'invalid_request';
    elsif exists (
      select 1 from public.organization_memberships target
      join public.profiles profile on profile.id = target.profile_id
      where target.id = p_membership_id and target.organization_id = p_organization_id
        and profile.auth_user_id = actor_auth
    ) then
      outcome := 'self_assignment_denied';
    elsif not exists (
      select 1 from public.hospitalizations h
      where h.id = p_hospitalization_id and h.organization_id = p_organization_id
        and h.status not in ('cancelled', 'entered_in_error')
    ) then
      outcome := 'resource_denied';
    elsif not exists (
      select 1 from public.organization_memberships target
      join public.profiles profile on profile.id = target.profile_id
      where target.id = p_membership_id and target.organization_id = p_organization_id
        and profile.status = 'active' and target.status = 'active'
        and target.valid_from <= pg_catalog.now()
        and (target.valid_until is null or target.valid_until > pg_catalog.now())
        and exists (
          select 1 from public.role_assignments ra
          join public.roles role on role.id = ra.role_id and role.organization_id = ra.organization_id
          join public.role_permissions rp on rp.role_id = role.id and rp.organization_id = role.organization_id
          join public.permission_catalog pc on pc.code = rp.permission_code
          where ra.organization_id = target.organization_id and ra.membership_id = target.id
            and ra.revoked_at is null and ra.valid_from <= pg_catalog.now()
            and (ra.valid_until is null or ra.valid_until > pg_catalog.now())
            and role.status = 'active' and pc.code = 'clinical.assigned.read' and pc.status = 'active'
        )
    ) then
      outcome := 'target_not_eligible';
    elsif exists (
      select 1 from public.care_assignments ca
      where ca.organization_id = p_organization_id and ca.hospitalization_id = p_hospitalization_id
        and ca.membership_id = p_membership_id and ca.revoked_at is null
        and pg_catalog.tstzrange(ca.valid_from, ca.valid_until, '[)') && pg_catalog.tstzrange(p_valid_from, p_valid_until, '[)')
    ) then
      outcome := 'overlap';
    else
      begin
        insert into public.care_assignments (
          organization_id, hospitalization_id, membership_id, valid_from, valid_until, created_by_membership_id
        ) values (p_organization_id, p_hospitalization_id, p_membership_id, p_valid_from, p_valid_until, actor_membership)
        returning id into new_assignment;
        outcome := 'granted'; success := true;
      exception when exclusion_violation or unique_violation then
        outcome := 'overlap';
      end;
    end if;
  elsif p_action = 'care_assignment.revoke' then
    if p_assignment_id is null or p_hospitalization_id is not null or p_membership_id is not null
       or p_valid_from is not null or p_valid_until is not null then
      outcome := 'invalid_request';
    else
      select ca.id into new_assignment from public.care_assignments ca
      where ca.id = p_assignment_id and ca.organization_id = p_organization_id
      for update;
      if new_assignment is null then
        outcome := 'resource_denied';
      else
        update public.care_assignments ca set revoked_at = pg_catalog.now(), revoked_by_membership_id = actor_membership
        where ca.id = p_assignment_id and ca.organization_id = p_organization_id and ca.revoked_at is null;
        if found then outcome := 'revoked'; success := true;
        else outcome := 'already_revoked'; success := true;
        end if;
      end if;
    end if;
  else
    outcome := 'invalid_request';
  end if;

  insert into public.audit_events (
    organization_id, actor_auth_user_id, actor_membership_id, action, target_type,
    target_id, result, idempotency_key, metadata
  ) values (
    p_organization_id, actor_auth, actor_membership, p_action, 'care_assignment', new_assignment,
    case when success then 'allowed' else 'denied' end, p_idempotency_key,
    pg_catalog.jsonb_build_object('request', signature, 'result_code', outcome)
  );
  return query select success, new_assignment, outcome, false;
end;
$$;

create or replace function public.grant_care_assignment(
  p_organization_id uuid, p_hospitalization_id uuid, p_membership_id uuid,
  p_valid_from timestamptz, p_valid_until timestamptz, p_idempotency_key uuid
)
returns table (result boolean, assignment_id uuid, result_code text, replayed boolean)
language sql security definer set search_path = '' as $$
  select * from private.care_assignment_operation(
    'care_assignment.grant', p_organization_id, p_hospitalization_id, p_membership_id,
    p_valid_from, p_valid_until, null::uuid, p_idempotency_key)
$$;

create or replace function public.revoke_care_assignment(
  p_organization_id uuid, p_assignment_id uuid, p_idempotency_key uuid
)
returns table (result boolean, assignment_id uuid, result_code text, replayed boolean)
language sql security definer set search_path = '' as $$
  select * from private.care_assignment_operation(
    'care_assignment.revoke', p_organization_id, null::uuid, null::uuid,
    null::timestamptz, null::timestamptz, p_assignment_id, p_idempotency_key)
$$;

alter function private.care_assignment_operation(text, uuid, uuid, uuid, timestamptz, timestamptz, uuid, uuid) owner to postgres;
alter function public.grant_care_assignment(uuid, uuid, uuid, timestamptz, timestamptz, uuid) owner to postgres;
alter function public.revoke_care_assignment(uuid, uuid, uuid) owner to postgres;
revoke all on function private.care_assignment_operation(text, uuid, uuid, uuid, timestamptz, timestamptz, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.grant_care_assignment(uuid, uuid, uuid, timestamptz, timestamptz, uuid) from public, anon, service_role;
revoke all on function public.revoke_care_assignment(uuid, uuid, uuid) from public, anon, service_role;
grant execute on function public.grant_care_assignment(uuid, uuid, uuid, timestamptz, timestamptz, uuid) to authenticated;
grant execute on function public.revoke_care_assignment(uuid, uuid, uuid) to authenticated;

comment on table public.audit_events is 'Sanitized append-only audit events. Runtime insertion is limited to controlled database operations.';
comment on function public.grant_care_assignment(uuid, uuid, uuid, timestamptz, timestamptz, uuid) is 'Transactional assignment grant; actor is derived exclusively from auth.uid().';
comment on function public.revoke_care_assignment(uuid, uuid, uuid) is 'Transactional assignment revoke; actor is derived exclusively from auth.uid().';
