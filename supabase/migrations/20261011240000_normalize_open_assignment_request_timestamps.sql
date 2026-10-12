-- Normalize each present request timestamp independently; open-ended grants have
-- valid_until = JSON null and still need their valid_from canonicalized.
set local time zone 'UTC';

drop trigger audit_events_append_only on public.audit_events;

with normalized_valid_from as (
  select event.id,
    case
      when pg_catalog.jsonb_typeof(event.metadata #> '{request,valid_from}') = 'string'
      then pg_catalog.jsonb_set(
        event.metadata,
        '{request,valid_from}',
        pg_catalog.to_jsonb((event.metadata #>> '{request,valid_from}')::timestamptz),
        false
      )
      else event.metadata
    end as metadata
  from public.audit_events event
  where event.metadata ? 'request'
    and pg_catalog.jsonb_typeof(event.metadata->'request') = 'object'
)
update public.audit_events event
set metadata = case
  when pg_catalog.jsonb_typeof(event.metadata #> '{request,valid_until}') = 'string'
  then pg_catalog.jsonb_set(
    normalized.metadata,
    '{request,valid_until}',
    pg_catalog.to_jsonb((event.metadata #>> '{request,valid_until}')::timestamptz),
    false
  )
  else normalized.metadata
end
from normalized_valid_from normalized
where normalized.id = event.id
  and (
    pg_catalog.jsonb_typeof(event.metadata #> '{request,valid_from}') = 'string'
    or pg_catalog.jsonb_typeof(event.metadata #> '{request,valid_until}') = 'string'
  );

create trigger audit_events_append_only
  before insert or update or delete on public.audit_events
  for each row execute function private.protect_audit_event_dml();

comment on table public.audit_events is
  'Append-only audit. Timestamp normalization of historical request metadata is performed only by explicit migrations.';
