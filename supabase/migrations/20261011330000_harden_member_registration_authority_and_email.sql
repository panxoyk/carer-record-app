-- 4.2 corrective hardening: bind the created Auth identity to the requested email
-- and audit resolvable permission denials before returning a stable response.
create or replace function public.preflight_organization_member_registration(
  p_organization_id uuid, p_email text, p_display_name text, p_role_id uuid, p_idempotency_key uuid
)
returns table(result_code text, profile_id uuid, membership_id uuid, assignment_id uuid, replayed boolean)
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid(); actor_membership uuid; prior private.organization_member_registrations%rowtype;
  prior_audit public.audit_events%rowtype; request_hash text; organization_active boolean;
begin
  if p_organization_id is null or p_idempotency_key is null or p_role_id is null
     or p_email is null or p_display_name is null then
    return query select 'invalid_request',null::uuid,null::uuid,null::uuid,false; return;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_organization_id::text||':'||coalesce(actor::text,'')||':iam.member.register:'||p_idempotency_key::text,0));
  select m.id into actor_membership from public.profiles p join public.organization_memberships m on m.profile_id=p.id
    where p.auth_user_id=actor and p.status='active' and m.organization_id=p_organization_id
      and m.status='active' and m.valid_from<=now() and (m.valid_until is null or m.valid_until>now());
  select exists(select 1 from public.organizations o where o.id=p_organization_id and o.status='active')
    into organization_active;
  -- An unresolved actor/tenant stays opaque and does not create an audit row.
  if actor_membership is null or not organization_active then
    return query select 'denied',null::uuid,null::uuid,null::uuid,false; return;
  end if;
  request_hash := pg_catalog.md5(pg_catalog.jsonb_build_object(
    'email',pg_catalog.lower(pg_catalog.btrim(p_email)),'display_name',pg_catalog.btrim(p_display_name),
    'role_id',p_role_id)::text);

  -- Do not reveal whether an existing key has a different payload until authority is current.
  if not public.has_active_iam_permission(p_organization_id,'iam.membership.manage')
     or not public.has_active_iam_permission(p_organization_id,'iam.role.assign') then
    select * into prior_audit from public.audit_events e where e.organization_id=p_organization_id
      and e.actor_auth_user_id=actor and e.action='iam.member.register' and e.idempotency_key=p_idempotency_key;
    if not found then
      insert into public.audit_events(organization_id,actor_auth_user_id,actor_membership_id,action,target_type,
        target_id,result,idempotency_key,metadata)
      values(p_organization_id,actor,actor_membership,'iam.member.register','profile',null,'denied',p_idempotency_key,
        pg_catalog.jsonb_build_object('request_hash',request_hash,'result_code','denied'));
    end if;
    return query select 'denied',null::uuid,null::uuid,null::uuid,false; return;
  end if;

  select * into prior from private.organization_member_registrations r
   where r.organization_id=p_organization_id and r.actor_auth_user_id=actor and r.idempotency_key=p_idempotency_key;
  if found then
    if prior.request_hash<>request_hash then
      return query select 'idempotency_conflict',null::uuid,null::uuid,null::uuid,false;
    else
      return query select prior.result_code,prior.profile_id,prior.membership_id,prior.assignment_id,true;
    end if;
    return;
  end if;
  select * into prior_audit from public.audit_events e where e.organization_id=p_organization_id
    and e.actor_auth_user_id=actor and e.action='iam.member.register' and e.idempotency_key=p_idempotency_key;
  if found then
    if prior_audit.metadata->>'request_hash' is distinct from request_hash then
      return query select 'idempotency_conflict',null::uuid,null::uuid,null::uuid,false;
    else
      return query select coalesce(prior_audit.metadata->>'result_code','denied'),
        null::uuid,null::uuid,null::uuid,true;
    end if;
    return;
  end if;
  if not exists(select 1 from public.roles r where r.id=p_role_id and r.organization_id=p_organization_id
      and r.status='active' and r.protected_kind is null
      and not exists(select 1 from public.role_permissions rp join public.permission_catalog pc on pc.code=rp.permission_code
        where rp.organization_id=r.organization_id and rp.role_id=r.id
          and (pc.status<>'active' or pc.delegation_policy<>'ordinary'
            or not public.has_active_iam_permission(p_organization_id,pc.code)))) then
    insert into public.audit_events(organization_id,actor_auth_user_id,actor_membership_id,action,target_type,target_id,result,idempotency_key,metadata)
      values(p_organization_id,actor,actor_membership,'iam.member.register','role',p_role_id,'denied',p_idempotency_key,
        pg_catalog.jsonb_build_object('request_hash',request_hash,'result_code','role_not_delegable'));
    return query select 'role_not_delegable',null::uuid,null::uuid,null::uuid,false; return;
  end if;
  return query select 'ready',null::uuid,null::uuid,null::uuid,false;
end $$;

create or replace function public.register_organization_member(
  p_organization_id uuid, p_auth_user_id uuid, p_email text, p_display_name text,
  p_role_id uuid, p_idempotency_key uuid
)
returns table(profile_id uuid, membership_id uuid, assignment_id uuid, result_code text, replayed boolean)
language plpgsql security definer set search_path = '' set timezone = 'UTC' as $$
declare
  actor uuid := auth.uid(); actor_membership uuid; request_hash text;
  prior private.organization_member_registrations%rowtype; prior_audit public.audit_events%rowtype;
  auth_email text; new_profile uuid; new_membership uuid; new_assignment uuid; outcome text := 'denied';
begin
  if p_organization_id is null or p_auth_user_id is null or p_role_id is null or p_idempotency_key is null
     or p_display_name is null then
    return query select null::uuid,null::uuid,null::uuid,'invalid_request',false; return;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_organization_id::text||':'||coalesce(actor::text,'')||':iam.member.register:'||p_idempotency_key::text,0));
  select m.id into actor_membership from public.profiles p join public.organization_memberships m on m.profile_id=p.id
    where p.auth_user_id=actor and p.status='active' and m.organization_id=p_organization_id
      and m.status='active' and m.valid_from<=now() and (m.valid_until is null or m.valid_until>now());
  if actor_membership is null or not public.has_active_iam_permission(p_organization_id,'iam.membership.manage')
     or not public.has_active_iam_permission(p_organization_id,'iam.role.assign')
     or not exists(select 1 from public.organizations o where o.id=p_organization_id and o.status='active') then
    return query select null::uuid,null::uuid,null::uuid,'denied',false; return;
  end if;
  request_hash := pg_catalog.md5(pg_catalog.jsonb_build_object(
    'email',pg_catalog.lower(pg_catalog.btrim(p_email)),'display_name',pg_catalog.btrim(p_display_name),
    'role_id',p_role_id)::text);
  select * into prior from private.organization_member_registrations r
   where r.organization_id=p_organization_id and r.actor_auth_user_id=actor and r.idempotency_key=p_idempotency_key;
  if found then
    if prior.request_hash<>request_hash or prior.auth_user_id<>p_auth_user_id then
      return query select null::uuid,null::uuid,null::uuid,'idempotency_conflict',false;
    else return query select prior.profile_id,prior.membership_id,prior.assignment_id,prior.result_code,true; end if;
    return;
  end if;
  select * into prior_audit from public.audit_events e where e.organization_id=p_organization_id
    and e.actor_auth_user_id=actor and e.action='iam.member.register' and e.idempotency_key=p_idempotency_key;
  if found then
    if prior_audit.metadata->>'request_hash' is distinct from request_hash then
      return query select null::uuid,null::uuid,null::uuid,'idempotency_conflict',false;
    else return query select null::uuid,null::uuid,null::uuid,
      coalesce(prior_audit.metadata->>'result_code','denied'),true; end if;
    return;
  end if;

  select u.email into auth_email from auth.users u where u.id=p_auth_user_id;
  if p_auth_user_id=actor or p_email is null or auth_email is null
     or pg_catalog.lower(pg_catalog.btrim(auth_email)) is distinct from pg_catalog.lower(pg_catalog.btrim(p_email)) then
    outcome := 'invalid_request';
  elsif not exists(select 1 from public.roles r where r.id=p_role_id and r.organization_id=p_organization_id
      and r.status='active' and r.protected_kind is null
      and not exists(select 1 from public.role_permissions rp join public.permission_catalog pc on pc.code=rp.permission_code
        where rp.organization_id=r.organization_id and rp.role_id=r.id
          and (pc.status<>'active' or pc.delegation_policy<>'ordinary'
            or not public.has_active_iam_permission(p_organization_id,pc.code)))) then
    outcome := 'role_not_delegable';
  else
    begin
      insert into public.profiles(auth_user_id,display_name,status)
        values(p_auth_user_id,pg_catalog.btrim(p_display_name),'active') returning id into new_profile;
      insert into public.organization_memberships(organization_id,profile_id,status,valid_from)
        values(p_organization_id,new_profile,'active',now()) returning id into new_membership;
      insert into public.role_assignments(organization_id,membership_id,role_id,valid_from,created_by_membership_id)
        values(p_organization_id,new_membership,p_role_id,now(),actor_membership) returning id into new_assignment;
      outcome := 'registered';
    exception when unique_violation or exclusion_violation then
      outcome := 'conflict'; new_profile:=null; new_membership:=null; new_assignment:=null;
    end;
  end if;
  insert into public.audit_events(organization_id,actor_auth_user_id,actor_membership_id,action,target_type,target_id,result,idempotency_key,metadata)
    values(p_organization_id,actor,actor_membership,'iam.member.register','profile',new_profile,
      case when outcome='registered' then 'allowed' else 'denied' end,p_idempotency_key,
      pg_catalog.jsonb_build_object('request_hash',request_hash,'result_code',outcome));
  if outcome='registered' then
    insert into private.organization_member_registrations(organization_id,actor_auth_user_id,idempotency_key,
      request_hash,auth_user_id,profile_id,membership_id,assignment_id,result_code)
      values(p_organization_id,actor,p_idempotency_key,request_hash,p_auth_user_id,new_profile,new_membership,new_assignment,outcome);
  end if;
  return query select new_profile,new_membership,new_assignment,outcome,false;
end $$;

alter function public.preflight_organization_member_registration(uuid,text,text,uuid,uuid) owner to postgres;
alter function public.register_organization_member(uuid,uuid,text,text,uuid,uuid) owner to postgres;
revoke all on function public.preflight_organization_member_registration(uuid,text,text,uuid,uuid),
  public.register_organization_member(uuid,uuid,text,text,uuid,uuid) from public,anon,service_role;
grant execute on function public.preflight_organization_member_registration(uuid,text,text,uuid,uuid),
  public.register_organization_member(uuid,uuid,text,text,uuid,uuid) to authenticated;

comment on function public.register_organization_member(uuid,uuid,text,text,uuid,uuid) is
  'Registers only an Auth identity whose normalized Auth email matches the request; registration remains owner-controlled and caller-authorized.';
