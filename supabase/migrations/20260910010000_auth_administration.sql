-- Authentication and administration are intentionally isolated from clinical access.
create type public.practitioner_status as enum ('active', 'suspended');

alter table public.practitioners
  add column status public.practitioner_status not null default 'active';

-- Replace the temporary broad read policies from the bootstrap schema.
drop policy "authenticated users can read practitioners" on public.practitioners;
drop policy "authenticated users can read patients" on public.patients;
drop policy "authenticated users can read clinical events" on public.clinical_events;

create or replace function public.is_administrator()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.practitioners
    where id = auth.uid() and role = 'administrator' and status = 'active'
  );
$$;

grant execute on function public.is_administrator() to authenticated;

create policy "practitioners read own profile" on public.practitioners
  for select to authenticated using (id = auth.uid());
create policy "administrators list practitioners" on public.practitioners
  for select to authenticated using (public.is_administrator());
create policy "administrators insert practitioners" on public.practitioners
  for insert to authenticated with check (public.is_administrator());
create policy "administrators update practitioners" on public.practitioners
  for update to authenticated using (public.is_administrator()) with check (public.is_administrator());
create policy "administrators delete practitioners" on public.practitioners
  for delete to authenticated using (public.is_administrator());

-- No patient or clinical-event policy exists until the clinical permission matrix is designed.
revoke select on public.patients, public.clinical_events from authenticated;

