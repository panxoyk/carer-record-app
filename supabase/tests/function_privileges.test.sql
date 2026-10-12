begin;

create extension if not exists pgtap;

select plan(7);

select ok(
  not has_function_privilege('anon', 'public.is_administrator()', 'execute'),
  'anonymous users cannot execute the administrator helper'
);
select ok(
  to_regprocedure('public.can_read_patients()') is null
    and to_regprocedure('public.can_read_clinical_events()') is null,
  'legacy clinical authorization helpers are removed'
);

select ok(
  has_function_privilege('authenticated', 'public.is_administrator()', 'execute'),
  'authenticated users can execute the administrator helper through RLS'
);
select ok(
  has_function_privilege('authenticated', 'private.can_read_clinical_hospitalization(uuid,uuid,text)', 'execute'),
  'authenticated policies can invoke the scoped clinical authorization helper'
);

select ok(
  not has_function_privilege('authenticated', 'public.set_updated_at()', 'execute'),
  'authenticated users cannot invoke the updated-at trigger directly'
);
select ok(
  not has_function_privilege('authenticated', 'public.normalize_rut(text)', 'execute'),
  'authenticated users cannot invoke RUT normalization directly'
);
select ok(
  not has_function_privilege('authenticated', 'public.normalize_patient_rut()', 'execute'),
  'authenticated users cannot invoke the RUT trigger directly'
);

select * from finish();
rollback;
