-- Close payload edge cases and make concurrent idempotent retries deterministic.
create or replace function public.save_period_summary(
 p_id uuid,p_organization_id uuid,p_hospitalization_id uuid,p_patient_id uuid,
 p_from_utc timestamptz,p_to_utc timestamptz,p_timezone text,p_generated_at timestamptz,
 p_content text,p_model_version text,p_prompt_version text,p_selected_kinds text[],
 p_excluded_undated_count integer,p_sources jsonb
) returns public.period_summaries language plpgsql security definer
set search_path='' set timezone='UTC' as $$
declare existing public.period_summaries; result public.period_summaries; source jsonb; kind text;
begin
 if auth.uid() is null or p_id is null or p_organization_id is null or p_hospitalization_id is null
    or p_patient_id is null or p_from_utc is null or p_to_utc is null or p_timezone is null
    or p_generated_at is null or p_content is null or p_model_version is null or p_prompt_version is null
    or p_selected_kinds is null or p_excluded_undated_count is null or p_sources is null
    then raise exception 'invalid summary payload'; end if;
 if not coalesce(private.can_use_period_summary(p_organization_id,p_hospitalization_id),false) then raise exception 'not authorized' using errcode='42501'; end if;
 if not isfinite(p_from_utc) or not isfinite(p_to_utc) or not isfinite(p_generated_at)
    or p_from_utc>=p_to_utc or p_to_utc>now()+interval '1 minute'
    or p_generated_at>now()+interval '1 minute' or p_generated_at<now()-interval '1 year'
    then raise exception 'invalid summary interval'; end if;
 if btrim(p_content)='' or char_length(p_content)>20000
    or btrim(p_model_version)='' or length(p_model_version)>128
    or btrim(p_prompt_version)='' or length(p_prompt_version)>128
    or p_excluded_undated_count<0
    or cardinality(p_selected_kinds) not between 1 and 4
    or array_position(p_selected_kinds,null) is not null
    or (select count(distinct x) from unnest(p_selected_kinds) x)<>cardinality(p_selected_kinds)
    or exists(select 1 from unnest(p_selected_kinds) x where x not in ('context_note','Condition','Observation','MedicationRequest'))
    then raise exception 'invalid summary payload'; end if;
 if jsonb_typeof(p_sources)<>'array' or jsonb_array_length(p_sources) not between 1 and 1000
    or octet_length(p_sources::text)>262144 then raise exception 'invalid summary payload'; end if;
 if not exists(select 1 from pg_catalog.pg_timezone_names z where z.name=p_timezone)
    or not exists(select 1 from public.organizations o where o.id=p_organization_id and o.timezone=p_timezone)
    then raise exception 'invalid summary timezone'; end if;
 for source in select value from jsonb_array_elements(p_sources) loop
   if jsonb_typeof(source)<>'object'
      or (select array_agg(key order by key) from jsonb_object_keys(source) key) is distinct from array['id','kind','occurred_at','precision']::text[]
      or jsonb_typeof(source->'id') is distinct from 'string'
      or jsonb_typeof(source->'kind') is distinct from 'string'
      or jsonb_typeof(source->'occurred_at') is distinct from 'string'
      or jsonb_typeof(source->'precision') is distinct from 'string'
      or source->>'precision' not in ('instant','date')
      or source->>'kind' not in ('context_note','Condition','Observation','MedicationRequest')
      or length(source->>'id') not between 1 and 128
      or length(source->>'occurred_at') not between 1 and 64
      or not (source->>'kind'=any(p_selected_kinds)) then raise exception 'invalid summary source'; end if;
   begin
     if source->>'precision'='date' then
       if (source->>'occurred_at') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'invalid date'; end if;
       -- Date precision denotes the institution-local calendar day. The day
       -- overlaps [from,to) iff its local start is before to and next-day start after from.
       if ((source->>'occurred_at')::date::timestamp at time zone p_timezone)>=p_to_utc
          or (((source->>'occurred_at')::date+1)::timestamp at time zone p_timezone)<=p_from_utc
          then raise exception 'source outside range'; end if;
     else
       if (source->>'occurred_at') !~ '^\d{4}-\d{2}-\d{2}T.*(Z|[+-]\d{2}:\d{2})$' then raise exception 'offset required'; end if;
       if (source->>'occurred_at')::timestamptz<p_from_utc or (source->>'occurred_at')::timestamptz>=p_to_utc then raise exception 'source outside range'; end if;
     end if;
   exception when others then raise exception 'invalid summary source'; end;
 end loop;
 insert into public.period_summaries(id,organization_id,hospitalization_id,patient_id,author_id,from_utc,to_utc,timezone,generated_at,content,model_version,prompt_version,selected_kinds,excluded_undated_count,sources)
 values(p_id,p_organization_id,p_hospitalization_id,p_patient_id,auth.uid(),p_from_utc,p_to_utc,p_timezone,p_generated_at,p_content,p_model_version,p_prompt_version,p_selected_kinds,p_excluded_undated_count,p_sources)
 on conflict (id) do nothing returning * into result;
 if found then return result; end if;
 select * into existing from public.period_summaries where id=p_id;
 if existing.author_id=auth.uid() and existing.organization_id=p_organization_id and existing.hospitalization_id=p_hospitalization_id and existing.patient_id=p_patient_id and existing.from_utc=p_from_utc and existing.to_utc=p_to_utc and existing.timezone=p_timezone and existing.generated_at=p_generated_at and existing.content=p_content and existing.model_version=p_model_version and existing.prompt_version=p_prompt_version and existing.selected_kinds=p_selected_kinds and existing.excluded_undated_count=p_excluded_undated_count and existing.sources=p_sources then return existing; end if;
 raise exception 'summary id conflict';
end $$;
