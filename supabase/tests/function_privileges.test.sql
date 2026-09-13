begin;

create extension if not exists pgtap;

select plan(9);

select ok(
  not has_function_privilege('anon', 'public.is_administrator()', 'execute'),
  'anonymous users cannot execute the administrator helper'
);
select ok(
  not has_function_privilege('anon', 'public.can_read_patients()', 'execute'),
  'anonymous users cannot execute the patient authorization helper'
);
select ok(
  not has_function_privilege('anon', 'public.can_read_clinical_events()', 'execute'),
  'anonymous users cannot execute the clinical-event authorization helper'
);

select ok(
  has_function_privilege('authenticated', 'public.is_administrator()', 'execute'),
  'authenticated users can execute the administrator helper through RLS'
);
select ok(
  has_function_privilege('authenticated', 'public.can_read_patients()', 'execute'),
  'authenticated users can execute the patient authorization helper through RLS'
);
select ok(
  has_function_privilege('authenticated', 'public.can_read_clinical_events()', 'execute'),
  'authenticated users can execute the clinical-event authorization helper through RLS'
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
