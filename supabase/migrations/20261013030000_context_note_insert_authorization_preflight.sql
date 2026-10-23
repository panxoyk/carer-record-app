-- Reject unauthorized runtime inserts before taking an episode row lock or
-- revealing whether that episode is writable. Owner-controlled inserts retain
-- the closed-episode invariant, while publication remains race-ordered by lock.
create or replace function private.guard_context_note_episode_writable()
returns trigger language plpgsql security definer set search_path = '' as $$
declare episode_status text;
begin
  if auth.uid() is not null
    and not private.can_write_context_note(new.organization_id, new.hospitalization_id)
  then
    raise insufficient_privilege using message = 'permission denied';
  end if;

  select h.status into episode_status from public.hospitalizations h
   where h.organization_id = new.organization_id and h.id = new.hospitalization_id
   for update;

  if episode_status is null or episode_status not in ('admitted', 'temporarily_absent') then
    raise insufficient_privilege using message = 'permission denied';
  end if;
  return new;
end $$;
revoke all on function private.guard_context_note_episode_writable() from public, anon, authenticated, service_role;
