-- Phase 4.1 correction: close role delegation bypasses and canonicalize role payloads.
create or replace function private.iam_admin_operation(
  p_action text, p_organization_id uuid, p_target_id uuid, p_value text,
  p_valid_from timestamptz, p_valid_until timestamptz, p_permissions text[], p_key uuid
)
returns table(result boolean, target_id uuid, result_code text, replayed boolean)
language plpgsql security definer set search_path = '' set timezone = 'UTC' as $$
declare
  actor uuid := auth.uid(); actor_membership uuid; prior public.audit_events%rowtype;
  signature jsonb; outcome text := 'denied'; success boolean := false; result_target uuid;
  target_membership public.organization_memberships%rowtype; target_role public.roles%rowtype;
  assignment public.role_assignments%rowtype; is_admin boolean := false;
  canonical_permissions text[]; role_name text; role_description text;
begin
  if p_organization_id is null or p_key is null then
    return query select false, null::uuid, 'invalid_request', false; return;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_organization_id::text||':'||coalesce(actor::text,'')||':'||p_action||':'||p_key::text,0));
  select m.id into actor_membership from public.profiles p join public.organization_memberships m on m.profile_id=p.id
   where p.auth_user_id=actor and p.status='active' and m.organization_id=p_organization_id
     and m.status='active' and m.valid_from<=now() and (m.valid_until is null or m.valid_until>now());
  if actor_membership is null then return query select false,null::uuid,'denied',false; return; end if;

  if p_permissions is null then
    canonical_permissions := null;
  else
    select coalesce(pg_catalog.array_agg(distinct permission order by permission),array[]::text[])
      into canonical_permissions from pg_catalog.unnest(p_permissions) permission;
  end if;
  signature:=pg_catalog.jsonb_build_object('target_id',p_target_id,'value',p_value,'valid_from',p_valid_from,
    'valid_until',p_valid_until,'permissions',canonical_permissions);

  if p_action like 'iam.admin.%' then
    is_admin := public.has_active_iam_permission(p_organization_id,'iam.role.assign') and exists (
      select 1 from public.role_assignments ra join public.roles r on r.id=ra.role_id and r.organization_id=ra.organization_id
       where ra.organization_id=p_organization_id and ra.membership_id=actor_membership
         and ra.revoked_at is null and ra.valid_from<=now() and (ra.valid_until is null or ra.valid_until>now())
         and r.protected_kind='demo_administrator' and r.status='active');
  end if;
  if (p_action like 'iam.admin.%' and not is_admin)
     or (p_action not like 'iam.admin.%' and not public.has_active_iam_permission(p_organization_id,
        case when p_action='iam.membership.update' then 'iam.membership.manage'
             when p_action like 'iam.role_assignment.%' then 'iam.role.assign' else 'iam.role.manage' end))
     or not exists(select 1 from public.organizations o where o.id=p_organization_id and o.status='active') then
    if exists(select 1 from public.audit_events e where e.organization_id=p_organization_id
      and e.actor_auth_user_id=actor and e.action=p_action and e.idempotency_key=p_key) then
      return query select false,null::uuid,'denied',false; return;
    end if;
    insert into public.audit_events(organization_id,actor_auth_user_id,actor_membership_id,action,target_type,
      target_id,result,idempotency_key,metadata)
    values(p_organization_id,actor,actor_membership,p_action,
      case when p_action='iam.membership.update' then 'organization_membership'
        when p_action like 'iam.role.%' and p_action not like 'iam.role_assignment.%' then 'role'
        else 'role_assignment' end,null,'denied',p_key,
      pg_catalog.jsonb_build_object('request_hash',pg_catalog.md5(signature::text),'result_code','denied'));
    return query select false,null::uuid,'denied',false; return;
  end if;
  select * into prior from public.audit_events e where e.organization_id=p_organization_id
    and e.actor_auth_user_id=actor and e.action=p_action and e.idempotency_key=p_key;
  if found then
    if prior.metadata->>'request_hash' is distinct from pg_catalog.md5(signature::text) then
      return query select false,null::uuid,'idempotency_conflict',false;
    else return query select prior.result='allowed',prior.target_id,
      coalesce(prior.metadata->>'result_code','denied'),true; end if;
    return;
  end if;

  if not exists(select 1 from public.organizations o where o.id=p_organization_id and o.status='active') then
    outcome:='denied';
  elsif p_action='iam.membership.update' then
    select * into target_membership from public.organization_memberships m
      where m.id=p_target_id and m.organization_id=p_organization_id for update;
    if found and p_value in ('invited','active','suspended','ended')
      and (p_valid_until is null or p_valid_until>target_membership.valid_from) then
      if target_membership.status='active' and (p_value<>'active' or p_valid_until is not null and p_valid_until<=now()) then
        perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('iam-admin:'||p_organization_id::text,0));
        if exists(select 1 from public.role_assignments ra join public.roles r on r.id=ra.role_id and r.organization_id=ra.organization_id
          where ra.organization_id=p_organization_id and ra.membership_id=p_target_id and r.protected_kind='demo_administrator'
            and ra.revoked_at is null and ra.valid_from<=now() and (ra.valid_until is null or ra.valid_until>now()))
          and (select count(*) from public.role_assignments ra join public.roles r on r.id=ra.role_id and r.organization_id=ra.organization_id
            join public.organization_memberships m on m.id=ra.membership_id and m.organization_id=ra.organization_id
            join public.profiles pr on pr.id=m.profile_id where ra.organization_id=p_organization_id and r.protected_kind='demo_administrator'
            and r.status='active' and ra.revoked_at is null and ra.valid_from<=now() and (ra.valid_until is null or ra.valid_until>now())
            and m.status='active' and m.valid_from<=now() and (m.valid_until is null or m.valid_until>now()) and pr.status='active')<=1 then
          outcome:='last_administrator';
        else update public.organization_memberships set status=p_value,valid_until=p_valid_until where id=p_target_id;
          outcome:='updated';success:=true;result_target:=p_target_id; end if;
      else update public.organization_memberships set status=p_value,valid_until=p_valid_until where id=p_target_id;
        outcome:='updated';success:=true;result_target:=p_target_id; end if;
    else outcome:='invalid_request'; end if;
  elsif p_action in ('iam.role.create','iam.role.update','iam.role.deactivate','iam.role.permissions.replace') then
    if p_action in ('iam.role.create','iam.role.update') then
      begin
        role_name := (p_value::jsonb)->>0;
        role_description := (p_value::jsonb)->>1;
      exception when others then
        role_name:=null; role_description:=null;
      end;
    end if;
    if p_action='iam.role.create' then
      if p_target_id is null and nullif(trim(role_name),'') is not null and nullif(trim(role_description),'') is not null then
        begin
          insert into public.roles(organization_id,name,description,is_system,protected_kind,created_by_membership_id)
            values(p_organization_id,role_name,role_description,false,null,actor_membership) returning id into result_target;
          outcome:='created';success:=true;
        exception when unique_violation then outcome:='role_name_conflict';success:=false;result_target:=null;
        end;
      else outcome:='invalid_request'; end if;
    else
      select * into target_role from public.roles r where r.id=p_target_id and r.organization_id=p_organization_id for update;
      if not found or target_role.protected_kind is not null or target_role.is_system then outcome:='protected_or_missing';
      elsif p_action='iam.role.update' and nullif(trim(role_name),'') is not null and nullif(trim(role_description),'') is not null then
        begin
          update public.roles set name=role_name,description=role_description where id=p_target_id;
          outcome:='updated';success:=true;result_target:=p_target_id;
        exception when unique_violation then outcome:='role_name_conflict';success:=false;result_target:=null;
        end;
      elsif p_action='iam.role.deactivate' then
        update public.roles set status='inactive' where id=p_target_id;
        outcome:='deactivated';success:=true;result_target:=p_target_id;
      elsif p_action='iam.role.permissions.replace' and p_permissions is not null
        and not exists(select 1 from pg_catalog.unnest(canonical_permissions) c
          left join public.permission_catalog pc on pc.code=c
          where pc.code is null or pc.status<>'active' or pc.delegation_policy<>'ordinary'
            or not public.has_active_iam_permission(p_organization_id,c)) then
        delete from public.role_permissions rp where rp.organization_id=p_organization_id and rp.role_id=p_target_id;
        insert into public.role_permissions(organization_id,role_id,permission_code,granted_by_membership_id)
          select p_organization_id,p_target_id,c,actor_membership from pg_catalog.unnest(canonical_permissions) c;
        outcome:='permissions_replaced';success:=true;result_target:=p_target_id;
      else outcome:='permission_not_delegable'; end if;
    end if;
  elsif p_action in ('iam.role_assignment.grant','iam.admin.grant') then
    select m.* into target_membership from public.organization_memberships m join public.profiles p on p.id=m.profile_id
     where m.id=p_target_id and m.organization_id=p_organization_id and m.status='active' and m.valid_from<=now()
       and (m.valid_until is null or m.valid_until>now()) and p.status='active' for update of m;
    select * into target_role from public.roles r where r.organization_id=p_organization_id and r.id=p_value::uuid and r.status='active';
    if not found or target_membership.id is null or (select auth_user_id from public.profiles where id=target_membership.profile_id)=actor
       or p_valid_from is null or p_valid_until is not null and p_valid_until<=p_valid_from
       or (p_action='iam.admin.grant' and target_role.protected_kind is distinct from 'demo_administrator')
       or (p_action='iam.role_assignment.grant' and target_role.protected_kind is not null) then
      outcome:='invalid_request';
    elsif p_action='iam.role_assignment.grant' and exists(
      select 1 from public.role_permissions rp join public.permission_catalog pc on pc.code=rp.permission_code
      where rp.organization_id=p_organization_id and rp.role_id=target_role.id
        and (pc.status<>'active' or pc.delegation_policy<>'ordinary'
          or not public.has_active_iam_permission(p_organization_id,pc.code))) then
      outcome:='role_not_delegable';
    else
      if p_action='iam.admin.grant' then
        perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('iam-admin:'||p_organization_id::text,0));
      end if;
      if exists(select 1 from public.role_assignments ra where ra.organization_id=p_organization_id and ra.membership_id=p_target_id
        and ra.role_id=target_role.id and ra.revoked_at is null
        and pg_catalog.tstzrange(ra.valid_from,ra.valid_until,'[)') && pg_catalog.tstzrange(p_valid_from,p_valid_until,'[)')) then
        outcome:='overlap';
      else begin
        insert into public.role_assignments(organization_id,membership_id,role_id,valid_from,valid_until,created_by_membership_id)
          values(p_organization_id,p_target_id,target_role.id,p_valid_from,p_valid_until,actor_membership) returning id into result_target;
        outcome:='granted';success:=true;
      exception when exclusion_violation or unique_violation then outcome:='overlap'; end; end if;
    end if;
  elsif p_action in ('iam.role_assignment.revoke','iam.admin.revoke') then
    select ra.* into assignment from public.role_assignments ra join public.roles r on r.id=ra.role_id and r.organization_id=ra.organization_id
      where ra.id=p_target_id and ra.organization_id=p_organization_id
        and ((p_action='iam.admin.revoke' and r.protected_kind='demo_administrator')
          or (p_action='iam.role_assignment.revoke' and r.protected_kind is null)) for update of ra;
    if not found then outcome:='resource_denied';
    elsif p_action='iam.admin.revoke' and assignment.membership_id=actor_membership then
      outcome:='self_revocation_denied';
    else
      if p_action='iam.admin.revoke' then
        perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('iam-admin:'||p_organization_id::text,0));
      end if;
      if assignment.revoked_at is not null then outcome:='already_revoked';success:=true;result_target:=p_target_id;
      elsif p_action='iam.admin.revoke' and (select count(*) from public.role_assignments ra join public.roles r on r.id=ra.role_id and r.organization_id=ra.organization_id
        join public.organization_memberships m on m.id=ra.membership_id and m.organization_id=ra.organization_id join public.profiles pr on pr.id=m.profile_id
        where ra.organization_id=p_organization_id and r.protected_kind='demo_administrator' and r.status='active' and ra.revoked_at is null
        and ra.valid_from<=now() and (ra.valid_until is null or ra.valid_until>now()) and m.status='active' and m.valid_from<=now()
        and (m.valid_until is null or m.valid_until>now()) and pr.status='active')<=1 then outcome:='last_administrator';
      else update public.role_assignments set revoked_at=now(),revoked_by_membership_id=actor_membership where id=p_target_id;
        outcome:='revoked';success:=true;result_target:=p_target_id; end if;
    end if;
  else outcome:='invalid_request'; end if;
  insert into public.audit_events(organization_id,actor_auth_user_id,actor_membership_id,action,target_type,target_id,result,idempotency_key,metadata)
   values(p_organization_id,actor,actor_membership,p_action,
     case when p_action='iam.membership.update' then 'organization_membership'
       when p_action like 'iam.role.%' and p_action not like 'iam.role_assignment.%' then 'role' else 'role_assignment' end,
     result_target,case when success then 'allowed' else 'denied' end,p_key,
     pg_catalog.jsonb_build_object('request_hash',pg_catalog.md5(signature::text),'result_code',outcome));
  return query select success,result_target,outcome,false;
end $$;

create or replace function public.create_iam_role(p_organization_id uuid,p_name text,p_description text,p_idempotency_key uuid)
returns table(result boolean,target_id uuid,result_code text,replayed boolean)
language sql security definer set search_path='' as $$
  select * from private.iam_rpc('iam.role.create',$1,null,pg_catalog.jsonb_build_array($2,$3)::text,null,null,null,$4)
$$;
create or replace function public.update_iam_role(p_organization_id uuid,p_role_id uuid,p_name text,p_description text,p_idempotency_key uuid)
returns table(result boolean,target_id uuid,result_code text,replayed boolean)
language sql security definer set search_path='' as $$
  select * from private.iam_rpc('iam.role.update',$1,$2,pg_catalog.jsonb_build_array($3,$4)::text,null,null,null,$5)
$$;

alter function private.iam_admin_operation(text,uuid,uuid,text,timestamptz,timestamptz,text[],uuid) owner to postgres;
alter function public.create_iam_role(uuid,text,text,uuid) owner to postgres;
alter function public.update_iam_role(uuid,uuid,text,text,uuid) owner to postgres;
revoke all on function private.iam_admin_operation(text,uuid,uuid,text,timestamptz,timestamptz,text[],uuid) from public,anon,authenticated,service_role;
revoke all on function public.create_iam_role(uuid,text,text,uuid),public.update_iam_role(uuid,uuid,text,text,uuid) from public,anon,service_role;
grant execute on function public.create_iam_role(uuid,text,text,uuid),public.update_iam_role(uuid,uuid,text,text,uuid) to authenticated;

comment on function private.iam_admin_operation(text,uuid,uuid,text,timestamptz,timestamptz,text[],uuid) is
  'Phase 4.1 correction: refuses non-delegable target roles, preserves JSON-encoded role name/description separately, and hashes canonical permission sets for replay.';
