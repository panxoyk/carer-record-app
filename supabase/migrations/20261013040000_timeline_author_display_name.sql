-- Resolve note authors only in the context of an already readable timeline row.
-- The helper intentionally accepts no author/profile identifier from callers.
create or replace function private.context_note_timeline_author_name(
  p_note_id uuid,
  p_organization_id uuid,
  p_hospitalization_id uuid
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select p.display_name
    from public.context_notes n
    left join public.profiles p on p.auth_user_id = n.author_id
   where n.id = p_note_id
     and n.organization_id = p_organization_id
     and n.hospitalization_id = p_hospitalization_id
     and n.status = 'confirmed'
     and private.can_read_context_note(n.organization_id, n.hospitalization_id)
$$;

revoke all on function private.context_note_timeline_author_name(uuid, uuid, uuid)
  from public, anon, service_role;
grant execute on function private.context_note_timeline_author_name(uuid, uuid, uuid)
  to authenticated;
comment on function private.context_note_timeline_author_name(uuid, uuid, uuid) is
  'Returns a confirmed note author display name only for an exact note, tenant and episode readable by the current caller; never accepts an arbitrary author lookup.';

create or replace view public.clinical_timeline_by_hospitalization
with (security_invoker = true, security_barrier = true) as
select e.organization_id, e.hospitalization_id, e.id as event_id,
       e.kind::text, e.occurred_at, e.summary,
       e.patient_id, e.created_at,
       'clinical_event'::text as source_kind,
       null::text as author_display_name
from public.clinical_events e
union all
select n.organization_id, n.hospitalization_id, n.id,
       case when n.input_method = 'audio' then 'milestone_audio' else 'milestone' end,
       n.occurred_at,
       n.content,
       n.patient_id, n.created_at,
       'context_note'::text,
       private.context_note_timeline_author_name(n.id, n.organization_id, n.hospitalization_id)
from public.context_notes n
where n.status = 'confirmed';

revoke all on public.clinical_timeline_by_hospitalization from public, anon;
grant select on public.clinical_timeline_by_hospitalization to authenticated;
comment on view public.clinical_timeline_by_hospitalization is
  'Episode timeline of clinical events and confirmed context milestones. author_display_name is resolved from profiles only for the exact readable note; author UUID and email remain private.';
