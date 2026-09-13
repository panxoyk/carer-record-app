-- Authorization helpers run with a fixed, empty search path and expose only the
-- execution privileges required by authenticated RLS policies.
create or replace function public.is_administrator()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.practitioners
    where id = auth.uid()
      and role = 'administrator'
      and status = 'active'
  );
$$;

create or replace function public.can_read_patients()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.practitioners
    where id = auth.uid()
      and status = 'active'
      and role in ('physician', 'nurse', 'technician')
  );
$$;

create or replace function public.can_read_clinical_events()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.can_read_patients();
$$;

revoke execute on function public.is_administrator() from public, anon;
revoke execute on function public.can_read_patients() from public, anon;
revoke execute on function public.can_read_clinical_events() from public, anon;

grant execute on function public.is_administrator() to authenticated;
grant execute on function public.can_read_patients() to authenticated;
grant execute on function public.can_read_clinical_events() to authenticated;

-- Trigger and normalization functions are implementation details, not RPCs.
revoke execute on function public.set_updated_at() from public, anon, authenticated;
revoke execute on function public.normalize_rut(text) from public, anon, authenticated;
revoke execute on function public.normalize_patient_rut() from public, anon, authenticated;
