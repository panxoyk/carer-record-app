-- Unit enumeration is an institutional permission, not an incidental result of
-- active membership or clinical census/assignment access.
drop policy "active members read units" on public.units;

create policy "authorized members read units" on public.units for select to authenticated
  using (public.has_active_iam_permission(organization_id, 'org.unit.read'));

comment on policy "authorized members read units" on public.units is
  'Requires effective org.unit.read in the same active organization.';
