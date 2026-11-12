-- Immutable, author-scoped historical period summaries (ADR-021).
insert into public.permission_catalog(code,family,description,delegation_policy)
values ('clinical.summary.use','clinical','Create and read own period summaries.','ordinary')
on conflict (code) do nothing;

-- Seed the demo clinical role and protected administrator without relying on
-- role names at runtime. Existing role composition is otherwise untouched.
insert into public.role_permissions(organization_id,role_id,permission_code)
select r.organization_id,r.id,'clinical.summary.use'
from public.roles r join public.organizations o on o.id=r.organization_id
where o.slug='demo-hospital'
  and (r.protected_kind='demo_administrator' or exists (
    select 1 from public.role_permissions rp
    where rp.organization_id=r.organization_id and rp.role_id=r.id
      and rp.permission_code='clinical.timeline.read'
  ))
on conflict do nothing;

create table public.period_summaries (
  id uuid primary key,
  organization_id uuid not null references public.organizations(id),
  hospitalization_id uuid not null,
  patient_id uuid not null,
  author_id uuid not null,
  from_utc timestamptz not null,
  to_utc timestamptz not null,
  timezone text not null,
  generated_at timestamptz not null,
  created_at timestamptz not null default now(),
  content text not null,
  model_version text not null,
  prompt_version text not null,
  selected_kinds text[] not null,
  excluded_undated_count integer not null default 0,
  sources jsonb not null,
  constraint period_summaries_episode_patient_fk foreign key
    (organization_id,hospitalization_id,patient_id)
    references public.hospitalizations(organization_id,id,patient_id) on delete restrict,
  constraint period_summaries_window check (from_utc < to_utc and to_utc <= now() + interval '1 minute'),
  constraint period_summaries_content check (char_length(content) between 1 and 20000),
  constraint period_summaries_timezone check (length(timezone) between 1 and 128),
  constraint period_summaries_versions check (length(model_version) between 1 and 128 and length(prompt_version) between 1 and 128),
  constraint period_summaries_kinds check (cardinality(selected_kinds) <= 5 and selected_kinds <@ array['context_note','Condition','Observation','MedicationRequest']::text[]),
  constraint period_summaries_undated check (excluded_undated_count >= 0),
  constraint period_summaries_sources check (jsonb_typeof(sources)='array' and jsonb_array_length(sources)<=1000)
);
create index period_summaries_author_episode_idx on public.period_summaries(organization_id,hospitalization_id,author_id,created_at desc);
alter table public.period_summaries enable row level security;

create or replace function private.can_use_period_summary(p_org uuid,p_episode uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select public.has_active_iam_permission(p_org,'clinical.summary.use')
 and public.has_active_iam_permission(p_org,'clinical.census.read')
 and public.has_active_iam_permission(p_org,'clinical.patient.read')
 and public.has_active_iam_permission(p_org,'clinical.timeline.read')
 and public.has_active_iam_permission(p_org,'context.note.read')
 and private.can_read_clinical_hospitalization(p_org,p_episode,'clinical.timeline.read') $$;
revoke all on function private.can_use_period_summary(uuid,uuid) from public,anon;
grant execute on function private.can_use_period_summary(uuid,uuid) to authenticated;

create policy period_summaries_read_own on public.period_summaries for select to authenticated
using (author_id=auth.uid() and private.can_use_period_summary(organization_id,hospitalization_id));
revoke all on public.period_summaries from public,anon,authenticated,service_role;
grant select on public.period_summaries to authenticated;

create or replace function public.period_summary_context(p_organization_id uuid,p_hospitalization_id uuid)
returns table(patient_id uuid,timezone text) language sql stable security definer set search_path=''
as $$ select h.patient_id,o.timezone from public.hospitalizations h
 join public.organizations o on o.id=h.organization_id
 where h.organization_id=p_organization_id and h.id=p_hospitalization_id
 and private.can_use_period_summary(h.organization_id,h.id) $$;
revoke all on function public.period_summary_context(uuid,uuid) from public,anon,service_role;
grant execute on function public.period_summary_context(uuid,uuid) to authenticated;

create or replace function public.save_period_summary(
 p_id uuid,p_organization_id uuid,p_hospitalization_id uuid,p_patient_id uuid,
 p_from_utc timestamptz,p_to_utc timestamptz,p_timezone text,p_generated_at timestamptz,
 p_content text,p_model_version text,p_prompt_version text,p_selected_kinds text[],
 p_excluded_undated_count integer,p_sources jsonb
) returns public.period_summaries language plpgsql security definer
set search_path='' set timezone='UTC' as $$
declare existing public.period_summaries; result public.period_summaries; source jsonb;
begin
 if auth.uid() is null then raise exception 'not authorized' using errcode='42501'; end if;
 if not private.can_use_period_summary(p_organization_id,p_hospitalization_id) then raise exception 'not authorized' using errcode='42501'; end if;
 if p_sources is null or jsonb_typeof(p_sources)<>'array' or jsonb_array_length(p_sources)>1000 then raise exception 'invalid summary payload'; end if;
 for source in select value from jsonb_array_elements(p_sources) loop
   if jsonb_typeof(source)<>'object' or (select array_agg(key order by key) from jsonb_object_keys(source) key) <> array['id','kind','occurred_at','precision']::text[]
      or jsonb_typeof(source->'id')<>'string' or jsonb_typeof(source->'kind')<>'string'
      or jsonb_typeof(source->'occurred_at')<>'string'
      or source->>'precision' not in ('instant','date')
      or source->>'kind' not in ('context_note','Condition','Observation','MedicationRequest')
      or length(source->>'id') not between 1 and 128
      or (source->>'precision'='date' and (source->>'occurred_at') !~ '^\d{4}-\d{2}-\d{2}$')
      or (source->>'precision'='instant' and (source->>'occurred_at') !~ '^\d{4}-\d{2}-\d{2}T') then
   raise exception 'invalid summary source';
   end if;
   if not (source->>'kind'=any(p_selected_kinds)) then raise exception 'invalid summary source'; end if;
   begin
     if source->>'precision'='date' then perform (source->>'occurred_at')::date;
     else perform (source->>'occurred_at')::timestamptz; end if;
   exception when others then raise exception 'invalid summary source';
   end;
 end loop;
 if not exists(select 1 from pg_catalog.pg_timezone_names z where z.name=p_timezone)
    or not exists(select 1 from public.organizations o where o.id=p_organization_id and o.timezone=p_timezone) then raise exception 'invalid summary timezone'; end if;
 if p_generated_at > now()+interval '1 minute' or p_generated_at < now()-interval '1 year' then raise exception 'invalid generation time'; end if;
 select * into existing from public.period_summaries where id=p_id;
 if found then
  if existing.author_id=auth.uid() and existing.organization_id=p_organization_id and existing.hospitalization_id=p_hospitalization_id and existing.patient_id=p_patient_id and existing.from_utc=p_from_utc and existing.to_utc=p_to_utc and existing.timezone=p_timezone and existing.generated_at=p_generated_at and existing.content=p_content and existing.model_version=p_model_version and existing.prompt_version=p_prompt_version and existing.selected_kinds=p_selected_kinds and existing.excluded_undated_count=p_excluded_undated_count and existing.sources=p_sources then return existing; end if;
  raise exception 'summary id conflict';
 end if;
 insert into public.period_summaries(id,organization_id,hospitalization_id,patient_id,author_id,from_utc,to_utc,timezone,generated_at,content,model_version,prompt_version,selected_kinds,excluded_undated_count,sources)
 values(p_id,p_organization_id,p_hospitalization_id,p_patient_id,auth.uid(),p_from_utc,p_to_utc,p_timezone,p_generated_at,p_content,p_model_version,p_prompt_version,p_selected_kinds,p_excluded_undated_count,p_sources)
 returning * into result;
 return result;
end $$;
revoke all on function public.save_period_summary(uuid,uuid,uuid,uuid,timestamptz,timestamptz,text,timestamptz,text,text,text,text[],integer,jsonb) from public,anon,service_role;
grant execute on function public.save_period_summary(uuid,uuid,uuid,uuid,timestamptz,timestamptz,text,timestamptz,text,text,text,text[],integer,jsonb) to authenticated;
