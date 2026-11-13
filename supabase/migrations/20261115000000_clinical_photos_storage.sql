-- ADR-024 (revisión): las fotos clínicas tomadas en la app se guardan en un
-- bucket privado de Supabase Storage, junto a su nota de bitácora. Las fotos
-- que vienen del sistema clínico siguen leyéndose desde FHIR (solo lectura).
-- RLS sobre storage.objects es la autoridad; no hay URLs públicas.

-- 1. Bucket privado, inmutable, solo JPEG/PNG de hasta 5 MB.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('clinical-photos', 'clinical-photos', false, 5242880,
  array['image/jpeg', 'image/png'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- 2. Ruta fija: <organization_id>/<hospitalization_id>/<client_event_id>.jpg|png.
--    Devuelve los tres UUID o nada si la ruta no cumple el formato.
create or replace function private.clinical_photo_path_parts(p_name text)
returns table(organization_id uuid, hospitalization_id uuid, client_event_id uuid)
language sql immutable set search_path = '' as $$
  select m[1]::uuid, m[2]::uuid, m[3]::uuid
  from pg_catalog.regexp_match(p_name,
    '^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/'
    '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/'
    '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.(jpg|png)$') m
  where m is not null
$$;

-- 3. Subir: permiso de documentos clínicos, alcance de escritura de notas,
--    episodio abierto y una nota confirmada del propio autor con ese
--    client_event_id en el mismo episodio.
create or replace function private.can_store_clinical_photo(p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from private.clinical_photo_path_parts(p_name) p
    join public.hospitalizations h
      on h.organization_id = p.organization_id and h.id = p.hospitalization_id
    join public.context_notes n
      on n.organization_id = p.organization_id
     and n.hospitalization_id = p.hospitalization_id
     and n.client_event_id = p.client_event_id
    where h.status in ('admitted', 'temporarily_absent')
      and n.author_id = auth.uid()
      and n.status = 'confirmed'
      and public.has_active_iam_permission(p.organization_id, 'clinical.document.create')
      and private.can_write_context_note(p.organization_id, p.hospitalization_id)
  )
$$;

-- 4. Leer: el mismo alcance que permite leer las notas del episodio.
create or replace function private.can_read_clinical_photo(p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from private.clinical_photo_path_parts(p_name) p
    where private.can_read_context_note(p.organization_id, p.hospitalization_id)
  )
$$;

revoke all on function private.clinical_photo_path_parts(text) from public, anon, service_role;
revoke all on function private.can_store_clinical_photo(text) from public, anon, service_role;
revoke all on function private.can_read_clinical_photo(text) from public, anon, service_role;
grant execute on function private.clinical_photo_path_parts(text) to authenticated;
grant execute on function private.can_store_clinical_photo(text) to authenticated;
grant execute on function private.can_read_clinical_photo(text) to authenticated;

-- Solo insert y select: una foto publicada no se reemplaza ni se borra.
create policy "authors attach clinical photos to own notes"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'clinical-photos'
    and private.can_store_clinical_photo(name)
  );

create policy "members read clinical photos of readable episodes"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'clinical-photos'
    and private.can_read_clinical_photo(name)
  );

-- 5. La bitácora expone la ruta de la foto de cada nota (null si no tiene).
create or replace function private.context_note_photo_path(
  p_organization_id uuid, p_hospitalization_id uuid, p_client_event_id uuid
)
returns text language sql stable security definer set search_path = '' as $$
  select o.name
    from storage.objects o
   where p_client_event_id is not null
     and o.bucket_id = 'clinical-photos'
     and o.name in (
       p_organization_id || '/' || p_hospitalization_id || '/' || p_client_event_id || '.jpg',
       p_organization_id || '/' || p_hospitalization_id || '/' || p_client_event_id || '.png')
     and private.can_read_context_note(p_organization_id, p_hospitalization_id)
   order by o.created_at
   limit 1
$$;
revoke all on function private.context_note_photo_path(uuid, uuid, uuid)
  from public, anon, service_role;
grant execute on function private.context_note_photo_path(uuid, uuid, uuid)
  to authenticated;

create or replace view public.clinical_timeline_by_hospitalization
with (security_invoker = true, security_barrier = true) as
select e.organization_id, e.hospitalization_id, e.id as event_id,
       e.kind::text, e.occurred_at, e.summary,
       e.patient_id, e.created_at,
       'clinical_event'::text as source_kind,
       null::text as author_display_name,
       null::text as category,
       null::text as author_profession,
       null::uuid as client_event_id,
       null::text as photo_path
from public.clinical_events e
union all
select n.organization_id, n.hospitalization_id, n.id,
       case when n.input_method = 'audio' then 'milestone_audio' else 'milestone' end,
       n.occurred_at,
       n.content,
       n.patient_id, n.created_at,
       'context_note'::text,
       private.context_note_timeline_author_name(n.id, n.organization_id, n.hospitalization_id),
       n.category,
       n.author_profession,
       n.client_event_id,
       private.context_note_photo_path(n.organization_id, n.hospitalization_id, n.client_event_id)
from public.context_notes n
where n.status = 'confirmed';

revoke all on public.clinical_timeline_by_hospitalization from public, anon;
grant select on public.clinical_timeline_by_hospitalization to authenticated;
comment on view public.clinical_timeline_by_hospitalization is
  'Episode timeline of clinical events and confirmed context milestones with author-chosen category, author profession snapshot, note client event id and the private Storage path of its clinical photo (ADR-024). Author UUID and email remain private.';

-- 6. La escritura de fotos en FHIR queda retirada.
drop function if exists public.fhir_authorized_encounter_write_context(uuid, uuid);
