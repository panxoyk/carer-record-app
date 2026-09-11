-- The clinical permission matrix grants active care roles read-only patient access.
-- Administrators retain administrative access only and do not receive clinical access.
create or replace function public.can_read_patients()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.practitioners
    where id = auth.uid()
      and status = 'active'
      and role in ('physician', 'nurse', 'technician')
  );
$$;

grant execute on function public.can_read_patients() to authenticated;
grant select on public.patients to authenticated;

create policy "active care roles read patients" on public.patients
  for select to authenticated using (public.can_read_patients());
