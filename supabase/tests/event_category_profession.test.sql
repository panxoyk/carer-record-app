begin;
create extension if not exists pgtap;
select plan(23);

-- ADR-024 fixture: one author with a profession, one reader, one outsider.
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
) values
  ('e2000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','category-author@example.test','',now(),'{}','{}',now(),now(),'','','',''),
  ('e2000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','category-outsider@example.test','',now(),'{}','{}',now(),now(),'','','','');

insert into public.organizations (id, slug, display_name)
values ('e2100000-0000-0000-0000-000000000001','category-test','Category test');
insert into public.profiles (id, auth_user_id, display_name, status) values
  ('e2200000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001','Synthetic nurse','active'),
  ('e2200000-0000-0000-0000-000000000002','e2000000-0000-0000-0000-000000000002','Synthetic outsider','active');
insert into public.organization_memberships (id, organization_id, profile_id, status, profession) values
  ('e2300000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000001','e2200000-0000-0000-0000-000000000001','active','enfermeria'),
  ('e2300000-0000-0000-0000-000000000002','e2100000-0000-0000-0000-000000000001','e2200000-0000-0000-0000-000000000002','active',null);
insert into public.roles (id, organization_id, name, description) values
  ('e2400000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000001','Synthetic clinician','Synthetic test role');
insert into public.role_permissions (organization_id, role_id, permission_code)
select 'e2100000-0000-0000-0000-000000000001','e2400000-0000-0000-0000-000000000001', code
from (values ('clinical.assigned.read'),('clinical.census.read'),('clinical.patient.read'),
  ('clinical.timeline.read'),('context.note.read'),('context.note.create'),
  ('context.note.confirm'),('clinical.document.create')) as p(code);
alter table public.role_assignments disable trigger role_assignments_require_active_authority;
insert into public.role_assignments (id, organization_id, membership_id, role_id, valid_from) values
  ('e2500000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000001','e2300000-0000-0000-0000-000000000001','e2400000-0000-0000-0000-000000000001',now()-interval '1 day');
alter table public.role_assignments enable trigger role_assignments_require_active_authority;

insert into public.units (id, organization_id, code, display_name)
values ('e2600000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000001','surgery','Cirugía');
insert into public.patients (id, organization_id, given_name, family_name)
values ('e2700000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000001','Synthetic','Patient');
insert into public.hospitalizations (id, organization_id, patient_id, status, admitted_at)
values ('e2800000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000001','e2700000-0000-0000-0000-000000000001','admitted',now());
insert into public.hospitalization_locations (organization_id, hospitalization_id, unit_id, bed_label, started_at)
values ('e2100000-0000-0000-0000-000000000001','e2800000-0000-0000-0000-000000000001','e2600000-0000-0000-0000-000000000001','12',now());
insert into public.care_assignments (
  id, organization_id, hospitalization_id, membership_id, valid_from, created_by_membership_id
) values
  ('e2900000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000001','e2800000-0000-0000-0000-000000000001','e2300000-0000-0000-0000-000000000001',now()-interval '1 day','e2300000-0000-0000-0000-000000000001');

select ok(has_column_privilege('authenticated','public.context_notes','category','insert'),
  'authors may choose the category');
select ok(not has_column_privilege('authenticated','public.context_notes','author_profession','insert'),
  'authors cannot write their profession snapshot');

set local role authenticated;
select set_config('request.jwt.claim.sub','e2000000-0000-0000-0000-000000000001',true);
select lives_ok($$ insert into public.context_notes (
    organization_id, hospitalization_id, patient_id, input_method, content, client_event_id, category)
  values ('e2100000-0000-0000-0000-000000000001','e2800000-0000-0000-0000-000000000001',
    'e2700000-0000-0000-0000-000000000001','text','Curación realizada',
    'e2910000-0000-0000-0000-000000000001','procedimiento') $$,
  'author publishes a categorized note');
select throws_ok($$ insert into public.context_notes (
    organization_id, hospitalization_id, patient_id, input_method, content, client_event_id, category)
  values ('e2100000-0000-0000-0000-000000000001','e2800000-0000-0000-0000-000000000001',
    'e2700000-0000-0000-0000-000000000001','text','Categoría inválida',
    'e2910000-0000-0000-0000-000000000002','diagnostico_ia') $$,
  '23514', null, 'unknown categories are rejected');
select is((select category from public.clinical_timeline_by_hospitalization
  where hospitalization_id='e2800000-0000-0000-0000-000000000001' and source_kind='context_note'),
  'procedimiento', 'timeline exposes the chosen category');
select is((select author_profession from public.clinical_timeline_by_hospitalization
  where hospitalization_id='e2800000-0000-0000-0000-000000000001' and source_kind='context_note'),
  'enfermeria', 'timeline exposes the server-side profession snapshot');
select ok(public.context_note_publication_matches(
    'e2100000-0000-0000-0000-000000000001','e2800000-0000-0000-0000-000000000001',
    'e2700000-0000-0000-0000-000000000001','text','Curación realizada',null,
    'e2910000-0000-0000-0000-000000000001','procedimiento'),
  'reconciliation matches the exact categorized note');
select ok(not public.context_note_publication_matches(
    'e2100000-0000-0000-0000-000000000001','e2800000-0000-0000-0000-000000000001',
    'e2700000-0000-0000-0000-000000000001','text','Curación realizada',null,
    'e2910000-0000-0000-0000-000000000001','comunicacion'),
  'reconciliation rejects a different category');
select is((select unit_display_name from public.clinical_census_by_hospitalization
  where hospitalization_id='e2800000-0000-0000-0000-000000000001'),
  'Cirugía', 'assigned reader sees the service name in the census');
select is((select profession from public.iam_current_context limit 1),
  'enfermeria', 'current context exposes the member profession');
-- Clinical photos in Supabase Storage (ADR-024 revision).
select ok(private.can_store_clinical_photo('e2100000-0000-0000-0000-000000000001/e2800000-0000-0000-0000-000000000001/e2910000-0000-0000-0000-000000000001.jpg'),
  'author may attach a photo to an own confirmed note');
select ok(not private.can_store_clinical_photo('e2100000-0000-0000-0000-000000000001/e2800000-0000-0000-0000-000000000001/e2910000-0000-0000-0000-00000000ffff.jpg'),
  'a photo needs an existing note of the author');
select ok(not private.can_store_clinical_photo('e2100000-0000-0000-0000-000000000001/e2800000-0000-0000-0000-000000000001/e2910000-0000-0000-0000-000000000001.gif'),
  'only jpg and png paths are accepted');
select lives_ok($$ insert into storage.objects (bucket_id, name)
  values ('clinical-photos', 'e2100000-0000-0000-0000-000000000001/e2800000-0000-0000-0000-000000000001/e2910000-0000-0000-0000-000000000001.jpg') $$,
  'storage RLS accepts the photo of an own note');
select throws_ok($$ insert into storage.objects (bucket_id, name)
  values ('clinical-photos', 'e2100000-0000-0000-0000-000000000001/e2800000-0000-0000-0000-000000000001/e2910000-0000-0000-0000-00000000ffff.jpg') $$,
  '42501', null, 'storage RLS rejects a photo without its note');
select is((select photo_path from public.clinical_timeline_by_hospitalization
  where hospitalization_id='e2800000-0000-0000-0000-000000000001' and source_kind='context_note'),
  'e2100000-0000-0000-0000-000000000001/e2800000-0000-0000-0000-000000000001/e2910000-0000-0000-0000-000000000001.jpg', 'timeline exposes the private photo path');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','e2000000-0000-0000-0000-000000000002',true);
select is(private.census_unit_display_name('e2100000-0000-0000-0000-000000000001',
    'e2800000-0000-0000-0000-000000000001','e2600000-0000-0000-0000-000000000001'),
  null::text, 'outsider cannot resolve the service name');
select is((select count(*)::int from public.clinical_timeline_by_hospitalization
  where hospitalization_id='e2800000-0000-0000-0000-000000000001'),
  0, 'outsider cannot read categories or professions');
select ok(not private.can_read_clinical_photo('e2100000-0000-0000-0000-000000000001/e2800000-0000-0000-0000-000000000001/e2910000-0000-0000-0000-000000000001.jpg'),
  'outsider cannot read the photo');
select is((select count(*)::int from storage.objects where bucket_id='clinical-photos'),
  0, 'outsider sees no clinical photo objects');
select throws_ok($$ insert into storage.objects (bucket_id, name)
  values ('clinical-photos', 'e2100000-0000-0000-0000-000000000001/e2800000-0000-0000-0000-000000000001/e2910000-0000-0000-0000-000000000001.png') $$,
  '42501', null, 'outsider cannot attach photos');
reset role;

select ok(not has_function_privilege('anon',
  'private.can_store_clinical_photo(text)','execute'),
  'anonymous callers cannot evaluate photo storage');
select is((select count(*)::int from pg_policies
  where schemaname='storage' and tablename='objects'
    and cmd in ('UPDATE','DELETE','ALL')
    and coalesce(qual,'') || coalesce(with_check,'') like '%clinical-photos%'),
  0, 'clinical photos cannot be replaced or deleted');

select * from finish();
rollback;
