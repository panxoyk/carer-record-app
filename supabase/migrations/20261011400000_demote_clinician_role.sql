-- The seeded clinician role is tenant configuration, not a CRA-owned fixture.
--
-- The seed marked 'Personal clinico' is_system=true only because it was pre-seeded.
-- That marker conflated provenance with mutability: 20261011390000 had to split the
-- role-target guard so composition was permitted, leaving rename/deactivate blocked by
-- a field whose only real meaning is "shipped by CRA".
--
-- The demo administrator keeps is_system=true and protected_kind='demo_administrator':
-- its composition is migration-managed and it is the reserved-permission holder. This
-- migration only demotes the clinician role so an administrator can compose, rename and
-- deactivate it during onboarding, as any other tenant-created role.
--
-- Idempotent and scoped by protected_kind so an organization that already renamed or
-- replaced the role is not affected.
update public.roles
set is_system = false
where protected_kind is null
  and is_system
  and name = 'Personal clínico';

comment on column public.roles.is_system is
  'Provenance marker for roles shipped by CRA. Protected roles are always is_system; it does not by itself grant or deny composition, rename or deactivation.';