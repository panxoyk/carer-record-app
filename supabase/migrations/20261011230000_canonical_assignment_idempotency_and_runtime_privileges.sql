-- Canonicalize timestamp JSON signatures and close TRUNCATE/runtime privilege gaps.
set local time zone 'UTC';

-- Historical request timestamps were serialized using the caller's TimeZone. Normalize
-- them while this is an explicit schema migration, before making the audit trigger active.
drop trigger audit_events_append_only on public.audit_events;
update public.audit_events event
set metadata = jsonb_set(
  jsonb_set(
    event.metadata,
    '{request,valid_from}',
    pg_catalog.to_jsonb((event.metadata #>> '{request,valid_from}')::timestamptz),
    false
  ),
  '{request,valid_until}',
  pg_catalog.to_jsonb((event.metadata #>> '{request,valid_until}')::timestamptz),
  false
)
where event.metadata ? 'request'
  and event.metadata #>> '{request,valid_from}' is not null
  and event.metadata #>> '{request,valid_until}' is not null;
create trigger audit_events_append_only
  before insert or update or delete on public.audit_events
  for each row execute function private.protect_audit_event_dml();

-- jsonb_build_object(timestamptz) now emits a stable UTC representation for both
-- persisted requests and incoming retry signatures, independent of caller settings.
alter function private.care_assignment_operation(
  text, uuid, uuid, uuid, timestamptz, timestamptz, uuid, uuid
) set timezone = 'UTC';

-- service_role is BYPASSRLS and receives broad default table privileges in Supabase.
-- Revoke every runtime write path, including TRUNCATE (which does not fire row triggers).
revoke insert, update, delete, truncate on public.care_assignments
  from public, anon, authenticated, service_role;
grant select on public.care_assignments to authenticated;

comment on table public.care_assignments is
  'Runtime writes are permitted only inside owner-controlled SECURITY DEFINER assignment RPCs or migration/seed bridges; runtime roles cannot TRUNCATE.';
