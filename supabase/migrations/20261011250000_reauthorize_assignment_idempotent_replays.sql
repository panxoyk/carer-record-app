-- Revalidate current authority before disclosing any stored idempotent result.
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
language plpgsql security definer set search_path = '' set timezone = 'UTC' as $$
declare
  actor_auth uuid := auth.uid();
  actor_membership uuid;
  prior public.audit_events%rowtype;
  signature jsonb;
  new_assignment uuid;
  outcome text;
  success boolean := false;
  actor_authorized boolean := false;
begin
  if p_organization_id is null or p_idempotency_key is null then
    return query select false, null::uuid, 'invalid_request'::text, false;
    return;
  end if;
  -- Preserve per-key serialization for the authority check, replay lookup, and effect.
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

  -- Authority is intentionally checked before the audit lookup. An unauthorized
  -- replay is opaque: never return its prior result, target ID, or conflict status.
  select exists (
    select 1 from public.organizations organization
    where organization.id = p_organization_id and organization.status = 'active'
  ) and public.has_active_iam_permission(
    p_organization_id, 'clinical.assignment.manage'
  ) into actor_authorized;

  if not actor_authorized then
    select * into prior from public.audit_events event
    where event.organization_id = p_organization_id
      and event.actor_auth_user_id = actor_auth and event.action = p_action
      and event.idempotency_key = p_idempotency_key;
    if found then
      return query select false, null::uuid, 'denied'::text, false;
      return;
    end if;

    -- First denials for a resolvable actor remain auditable. A prior event with this
    -- unique actor/action/key is immutable and is not duplicated or modified.
    insert into public.audit_events (
      organization_id, actor_auth_user_id, actor_membership_id, action, target_type,
      target_id, result, idempotency_key, metadata
    ) values (
      p_organization_id, actor_auth, actor_membership, p_action, 'care_assignment', null,
      'denied', p_idempotency_key,
      pg_catalog.jsonb_build_object('request', signature, 'result_code', 'denied')
    );
    return query select false, null::uuid, 'denied'::text, false;
    return;
  end if;

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

  if p_action = 'care_assignment.grant' then
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

alter function private.care_assignment_operation(text, uuid, uuid, uuid, timestamptz, timestamptz, uuid, uuid) owner to postgres;
revoke all on function private.care_assignment_operation(text, uuid, uuid, uuid, timestamptz, timestamptz, uuid, uuid) from public, anon, authenticated, service_role;

comment on function private.care_assignment_operation(text, uuid, uuid, uuid, timestamptz, timestamptz, uuid, uuid) is
  'Revalidates active tenant and clinical.assignment.manage before replay lookup; unauthorized replay returns opaque denial without mutating audit history.';
