#!/usr/bin/env python3
"""Exercise the actual pre-IAM migration chain in a disposable Supabase project."""

from __future__ import annotations

import shutil
import socket
import subprocess
import tempfile
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "supabase" / "migrations"
BASELINE_VERSION = "20260912000000"
IAM_VERSIONS = {"20261011170000", "20261011180000", "20261011190000"}
PHASE2_VERSION = "20261011200000"
PHASE2_HARDENING_VERSION = "20261011210000"
PHASE2_OPERATIONS_VERSION = "20261011220000"
PHASE2_CANONICAL_VERSION = "20261011230000"
PHASE2_OPEN_TIMESTAMP_VERSION = "20261011240000"
PHASE2_REPLAY_GUARD_VERSION = "20261011250000"
PHASE2_UNIT_PERMISSION_VERSION = "20261011260000"
PHASE3_CLINICAL_RLS_VERSION = "20261011270000"
PHASE3_GATE_FIXES_VERSION = "20261011280000"
PHASE4_IAM_OPERATIONS_VERSION = "20261011290000"
PHASE4_IAM_CORRECTIONS_VERSION = "20261011300000"
PHASE4_ADMIN_ASSIGNED_READ_VERSION = "20261011310000"
PHASE4_MEMBER_REGISTRATION_VERSION = "20261011320000"
PHASE4_MEMBER_REGISTRATION_CORRECTIONS_VERSION = "20261011330000"
PHASE4_FLUTTER_READ_CONTRACTS_VERSION = "20261011340000"
PHASE4_READ_CONTRACT_HARDENING_VERSION = "20261011350000"
PHASE4_TARGET_HISTORY_VERSION = "20261011360000"
PHASE4_AUXILIARY_IAM_POLICY_VERSION = "20261011370000"
EXCLUDED_SERVICES = (
    "gotrue,realtime,storage-api,imgproxy,kong,postgrest,postgres-meta,"
    "studio,edge-runtime,logflare,vector,supavisor,mailpit"
)


def available_port() -> int:
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def run(*args: str, cwd: Path) -> str:
    result = subprocess.run(
        args, cwd=cwd, check=False, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    print(result.stdout, end="")
    if result.returncode:
        raise subprocess.CalledProcessError(result.returncode, args, output=result.stdout)
    return result.stdout


def run_sql(container: str, sql: str) -> None:
    result = subprocess.run(
        ["docker", "exec", "-i", container, "psql", "-U", "supabase_admin", "-d", "postgres", "-v", "ON_ERROR_STOP=1"],
        input=sql, text=True, check=False, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    print(result.stdout, end="")
    if result.returncode:
        raise subprocess.CalledProcessError(result.returncode, result.args, output=result.stdout)


def main() -> None:
    supabase = ["pnpm", "exec", "supabase"]
    temporary = Path(tempfile.mkdtemp(prefix="cra-iam-upgrade-"))
    project = temporary / "project"
    migration_dir = project / "supabase" / "migrations"
    migration_dir.mkdir(parents=True)
    project_id = f"cra-iam-upgrade-{uuid.uuid4().hex[:10]}"
    (project / "supabase" / "config.toml").write_text(
        f'project_id = "{project_id}"\n\n'
        "[api]\nenabled = false\n\n"
        f"[db]\nport = {available_port()}\nmajor_version = 17\n\n"
        "[studio]\nenabled = false\n\n"
        "[analytics]\nenabled = false\n"
    )
    for migration in sorted(MIGRATIONS.glob("*.sql")):
        if migration.name[:14] <= BASELINE_VERSION:
            shutil.copy2(migration, migration_dir / migration.name)

    started = False
    container = ""
    try:
        run(*supabase, "start", "--workdir", str(project), "--exclude", EXCLUDED_SERVICES,
            "--yes", cwd=ROOT)
        started = True
        names = subprocess.check_output(["docker", "ps", "--format", "{{.Names}}"], text=True).splitlines()
        container = next(name for name in names if name.startswith("supabase_db_") and project_id in name)

        # The Postgres-only instance intentionally omits GoTrue; provide only the minimal
        # synthetic Auth boundary required by the actual historical migrations.
        bootstrap = temporary / "auth-bootstrap.sql"
        bootstrap_statements = ["""
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
end $$
""", "create schema if not exists auth", "do $$ begin execute format('grant usage, create on schema auth to %I', current_user); end $$", "create table if not exists auth.users (id uuid primary key)", """create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$"""]
        for statement in bootstrap_statements:
            run_sql(container, statement)
        run(*supabase, "migration", "up", "--local", "--include-all", "--workdir", str(project), cwd=ROOT)

        auth_users = """
insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'),
  ('22222222-2222-2222-2222-222222222222'),
  ('33333333-3333-3333-3333-333333333333'),
  ('44444444-4444-4444-4444-444444444444'),
  ('55555555-5555-5555-5555-555555555555')
"""
        practitioners_sql = """
insert into public.practitioners (id, display_name, role, status) values
  ('11111111-1111-1111-1111-111111111111', 'Synthetic seed physician Ana', 'physician', 'active'),
  ('22222222-2222-2222-2222-222222222222', 'Synthetic seed nurse Matias', 'nurse', 'active'),
  ('33333333-3333-3333-3333-333333333333', 'Synthetic seed administrator', 'administrator', 'active'),
  ('44444444-4444-4444-4444-444444444444', 'Synthetic seed technician', 'technician', 'active'),
  ('55555555-5555-5555-5555-555555555555', 'Synthetic suspended physician', 'physician', 'suspended')
"""
        clinical_fixtures_sql = """
insert into public.patients (id, external_reference, given_name, family_name) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'UPGRADE-ELENA', 'Synthetic', 'Elena'),
  ('90000000-0000-0000-0000-000000000001', 'UPGRADE-UNKNOWN', 'Synthetic', 'Unmapped');
insert into public.clinical_events (id, patient_id, recorded_by, kind, occurred_at, payload) values
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'observation', now(), '{"summary":"Synthetic mapped event"}'),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 'procedure', now(), '{"summary":"Synthetic mapped event"}'),
  ('80000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'document', now(), '{"summary":"Synthetic mapped event"}'),
  ('80000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 'condition', now(), '{"summary":"Synthetic mapped event"}'),
  ('90000000-0000-0000-0000-000000000002', '90000000-0000-0000-0000-000000000001', '44444444-4444-4444-4444-444444444444', 'encounter', now(), '{"summary":"Synthetic unknown event"}');
"""
        for statement in (auth_users, practitioners_sql, clinical_fixtures_sql):
            run_sql(container, statement)

        for version in sorted(IAM_VERSIONS):
            migration = next(MIGRATIONS.glob(f"{version}_*.sql"))
            shutil.copy2(migration, migration_dir / migration.name)
        run(*supabase, "migration", "up", "--local", "--include-all", "--workdir", str(project), cwd=ROOT)

        phase2_migration = next(MIGRATIONS.glob(f"{PHASE2_VERSION}_*.sql"))
        shutil.copy2(phase2_migration, migration_dir / phase2_migration.name)
        run(*supabase, "migration", "up", "--local", "--include-all", "--workdir", str(project), cwd=ROOT)

        hardening_migration = next(MIGRATIONS.glob(f"{PHASE2_HARDENING_VERSION}_*.sql"))
        shutil.copy2(hardening_migration, migration_dir / hardening_migration.name)
        run(*supabase, "migration", "up", "--local", "--include-all", "--workdir", str(project), cwd=ROOT)

        operations_migration = next(MIGRATIONS.glob(f"{PHASE2_OPERATIONS_VERSION}_*.sql"))
        shutil.copy2(operations_migration, migration_dir / operations_migration.name)
        run(*supabase, "migration", "up", "--local", "--include-all", "--workdir", str(project), cwd=ROOT)

        # Create an open-ended grant through the actual RPC before 23000 runs. Its
        # historical JSON timestamp carries the caller's non-UTC offset and JSON null
        # for valid_until, reproducing the migration-compatibility case.
        run_sql(container, "select public.bootstrap_synthetic_hospitalization_fixtures()")
        run_sql(container, """
select set_config('cra.assignment.org', (select id::text from public.organizations where slug='demo-hospital'), false);
select set_config('cra.assignment.target', (
  select membership.id::text from public.organization_memberships membership
  join public.profiles profile on profile.id=membership.profile_id
  where profile.auth_user_id='22222222-2222-2222-2222-222222222222'
    and membership.organization_id=(select id from public.organizations where slug='demo-hospital')
), false);
set role authenticated;
set time zone 'America/Santiago';
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
do $$ declare reply record; begin
  select * into reply from public.grant_care_assignment(
    current_setting('cra.assignment.org')::uuid,
    'a1000000-0000-0000-0000-000000000001',
    current_setting('cra.assignment.target')::uuid,
    '2026-10-01 00:00:00+00', null,
    'a9500000-0000-0000-0000-000000000001'
  );
  if reply.result_code <> 'granted' or reply.replayed then
    raise exception 'pre-normalization RPC did not create the synthetic open grant';
  end if;
end $$;
reset role;
""")

        canonical_migration = next(MIGRATIONS.glob(f"{PHASE2_CANONICAL_VERSION}_*.sql"))
        shutil.copy2(canonical_migration, migration_dir / canonical_migration.name)
        run(*supabase, "migration", "up", "--local", "--include-all", "--workdir", str(project), cwd=ROOT)

        open_timestamp_migration = next(MIGRATIONS.glob(f"{PHASE2_OPEN_TIMESTAMP_VERSION}_*.sql"))
        shutil.copy2(open_timestamp_migration, migration_dir / open_timestamp_migration.name)
        run(*supabase, "migration", "up", "--local", "--include-all", "--workdir", str(project), cwd=ROOT)

        replay_guard_migration = next(MIGRATIONS.glob(f"{PHASE2_REPLAY_GUARD_VERSION}_*.sql"))
        shutil.copy2(replay_guard_migration, migration_dir / replay_guard_migration.name)
        run(*supabase, "migration", "up", "--local", "--include-all", "--workdir", str(project), cwd=ROOT)

        unit_permission_migration = next(MIGRATIONS.glob(f"{PHASE2_UNIT_PERMISSION_VERSION}_*.sql"))
        shutil.copy2(unit_permission_migration, migration_dir / unit_permission_migration.name)
        run(*supabase, "migration", "up", "--local", "--include-all", "--workdir", str(project), cwd=ROOT)

        clinical_rls_migration = next(MIGRATIONS.glob(f"{PHASE3_CLINICAL_RLS_VERSION}_*.sql"))
        shutil.copy2(clinical_rls_migration, migration_dir / clinical_rls_migration.name)
        run(*supabase, "migration", "up", "--local", "--include-all", "--workdir", str(project), cwd=ROOT)

        clinical_gate_migration = next(MIGRATIONS.glob(f"{PHASE3_GATE_FIXES_VERSION}_*.sql"))
        shutil.copy2(clinical_gate_migration, migration_dir / clinical_gate_migration.name)
        run(*supabase, "migration", "up", "--local", "--include-all", "--workdir", str(project), cwd=ROOT)

        phase4_migration = next(MIGRATIONS.glob(f"{PHASE4_IAM_OPERATIONS_VERSION}_*.sql"))
        shutil.copy2(phase4_migration, migration_dir / phase4_migration.name)
        run(*supabase, "migration", "up", "--local", "--include-all", "--workdir", str(project), cwd=ROOT)

        phase4_corrections_migration = next(MIGRATIONS.glob(f"{PHASE4_IAM_CORRECTIONS_VERSION}_*.sql"))
        shutil.copy2(phase4_corrections_migration, migration_dir / phase4_corrections_migration.name)
        run(*supabase, "migration", "up", "--local", "--include-all", "--workdir", str(project), cwd=ROOT)

        phase4_admin_permission_migration = next(MIGRATIONS.glob(f"{PHASE4_ADMIN_ASSIGNED_READ_VERSION}_*.sql"))
        if "on conflict (role_id,permission_code) do nothing" not in phase4_admin_permission_migration.read_text().lower():
            raise RuntimeError("protected assigned-read migration is not idempotent")
        shutil.copy2(phase4_admin_permission_migration, migration_dir / phase4_admin_permission_migration.name)
        run(*supabase, "migration", "up", "--local", "--include-all", "--workdir", str(project), cwd=ROOT)

        phase4_member_registration = next(MIGRATIONS.glob(f"{PHASE4_MEMBER_REGISTRATION_VERSION}_*.sql"))
        shutil.copy2(phase4_member_registration, migration_dir / phase4_member_registration.name)
        run(*supabase, "migration", "up", "--local", "--include-all", "--workdir", str(project), cwd=ROOT)

        phase4_member_registration_corrections = next(
            MIGRATIONS.glob(f"{PHASE4_MEMBER_REGISTRATION_CORRECTIONS_VERSION}_*.sql")
        )
        shutil.copy2(phase4_member_registration_corrections, migration_dir / phase4_member_registration_corrections.name)
        run(*supabase, "migration", "up", "--local", "--include-all", "--workdir", str(project), cwd=ROOT)

        phase4_flutter_read_contracts = next(
            MIGRATIONS.glob(f"{PHASE4_FLUTTER_READ_CONTRACTS_VERSION}_*.sql")
        )
        shutil.copy2(phase4_flutter_read_contracts, migration_dir / phase4_flutter_read_contracts.name)
        run(*supabase, "migration", "up", "--local", "--include-all", "--workdir", str(project), cwd=ROOT)

        phase4_read_contract_hardening = next(
            MIGRATIONS.glob(f"{PHASE4_READ_CONTRACT_HARDENING_VERSION}_*.sql")
        )
        shutil.copy2(phase4_read_contract_hardening, migration_dir / phase4_read_contract_hardening.name)
        run(*supabase, "migration", "up", "--local", "--include-all", "--workdir", str(project), cwd=ROOT)

        phase4_target_history = next(
            MIGRATIONS.glob(f"{PHASE4_TARGET_HISTORY_VERSION}_*.sql")
        )
        shutil.copy2(phase4_target_history, migration_dir / phase4_target_history.name)
        run(*supabase, "migration", "up", "--local", "--include-all", "--workdir", str(project), cwd=ROOT)

        phase4_auxiliary_iam_policy = next(
            MIGRATIONS.glob(f"{PHASE4_AUXILIARY_IAM_POLICY_VERSION}_*.sql")
        )
        shutil.copy2(phase4_auxiliary_iam_policy, migration_dir / phase4_auxiliary_iam_policy.name)
        run(*supabase, "migration", "up", "--local", "--include-all", "--workdir", str(project), cwd=ROOT)

        run_sql(container, """
set role authenticated;
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
do $$ begin
  if (select count(*) from public.iam_current_context) = 0 then
    raise exception 'phase 4.3 current IAM context is missing after upgrade';
  end if;
  if has_column_privilege('authenticated','public.profiles','auth_user_id','select') then
    raise exception 'phase 4.3 exposed auth_user_id';
  end if;
  if (select count(*) from public.iam_member_directory) = 0 then
    raise exception 'phase 4.3 tenant member directory is missing after upgrade';
  end if;
  if (select count(*) from public.roles where protected_kind is not null) = 0 then
    raise exception 'the existing iam.role.read policy no longer exposes protected roles to Admin';
  end if;
end $$;
reset role;
""")

        run_sql(container, """
select set_config('cra.upgrade.admin_role', (select id::text from public.roles
  where protected_kind='demo_administrator'), false);
select set_config('cra.upgrade.partial_actor_role', (select r.id::text
  from public.roles r
  join public.role_assignments ra on ra.role_id=r.id and ra.organization_id=r.organization_id
  join public.organization_memberships m on m.id=ra.membership_id and m.organization_id=ra.organization_id
  join public.profiles p on p.id=m.profile_id
  where p.auth_user_id='11111111-1111-1111-1111-111111111111'
    and r.protected_kind is null and r.status='active' and ra.revoked_at is null
  order by ra.id limit 1), false);
insert into public.role_permissions (organization_id, role_id, permission_code)
select organization_id, id, 'iam.membership.read' from public.roles
where id=current_setting('cra.upgrade.partial_actor_role')::uuid
on conflict (organization_id, role_id, permission_code) do nothing;
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
do $$ begin
  if not public.has_active_iam_permission(
    (select id from public.organizations where slug='demo-hospital'), 'iam.membership.read')
    or public.has_active_iam_permission(
    (select id from public.organizations where slug='demo-hospital'), 'clinical.assignment.manage')
    or public.has_active_iam_permission(
    (select id from public.organizations where slug='demo-hospital'), 'iam.role.read') then
    raise exception 'synthetic upgrade actor does not have the intended partial IAM permissions';
  end if;
  if not exists(select 1 from public.roles where protected_kind is null)
    or exists(select 1 from public.roles where protected_kind is not null)
    or exists(select 1 from public.role_permissions rp join public.roles r
      on r.organization_id=rp.organization_id and r.id=rp.role_id where r.protected_kind is not null)
    or exists(select 1 from public.role_permissions
      where role_id=current_setting('cra.upgrade.admin_role')::uuid)
    or exists(select 1 from public.role_assignments ra join public.roles r
      on r.organization_id=ra.organization_id and r.id=ra.role_id where r.protected_kind is not null)
    or exists(select 1 from public.role_assignments
      where role_id=current_setting('cra.upgrade.admin_role')::uuid)
    or exists(select 1 from public.iam_member_role_assignments where protected_kind is not null) then
    raise exception 'auxiliary IAM policies expose protected roles or assignments';
  end if;
end $$;
reset role;
delete from public.role_permissions
where role_id=current_setting('cra.upgrade.partial_actor_role')::uuid
  and permission_code='iam.membership.read';
""")

        run_sql(container, """
select set_config('cra.assignment.org', (select id::text from public.organizations where slug='demo-hospital'), false);
select set_config('cra.assignment.target', (
  select membership.id::text from public.organization_memberships membership
  join public.profiles profile on profile.id=membership.profile_id
  where profile.auth_user_id='22222222-2222-2222-2222-222222222222'
    and membership.organization_id=(select id from public.organizations where slug='demo-hospital')
), false);
set role authenticated;
set time zone 'UTC';
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
do $$
declare reply record; audit_count bigint; effect_count bigint;
begin
  select * into reply from public.grant_care_assignment(
    current_setting('cra.assignment.org')::uuid,
    'a1000000-0000-0000-0000-000000000001',
    current_setting('cra.assignment.target')::uuid,
    '2026-10-01 00:00:00+00', null,
    'a9500000-0000-0000-0000-000000000001'
  );
  if reply.result_code <> 'granted' or not reply.replayed then
    raise exception 'UTC replay of pre-hardening open grant did not return the previous result';
  end if;
  select count(*) into audit_count from public.audit_events
    where idempotency_key='a9500000-0000-0000-0000-000000000001';
  select count(*) into effect_count from public.care_assignments assignment
    join public.audit_events event on event.target_id=assignment.id
    where event.idempotency_key='a9500000-0000-0000-0000-000000000001';
  if audit_count <> 1 or effect_count <> 1 then
    raise exception 'UTC replay duplicated audit or assignment effect';
  end if;
end $$;
reset role;
""")

        checks = ["""
do $$
declare
  admin_role_id uuid;
  clinician_role_id uuid;
begin
  select id into strict admin_role_id from public.roles where protected_kind = 'demo_administrator';
  select id into strict clinician_role_id from public.roles where name = 'Personal clínico';
  if (select count(*) from public.profiles) <> 5 then raise exception 'upgrade did not backfill five profiles'; end if;
  if (select count(*) from public.organization_memberships) <> 5 then raise exception 'upgrade did not backfill five memberships'; end if;
  if (select count(*) from public.role_assignments where role_id = admin_role_id) <> 1 then raise exception 'administrator mapping failed'; end if;
  if (select count(*) from public.role_assignments where role_id = clinician_role_id) <> 2 then raise exception 'physician/nurse mapping failed'; end if;
  if exists (
    select 1 from public.role_assignments assignment
    join public.organization_memberships membership on membership.id = assignment.membership_id
    join public.profiles profile on profile.id = membership.profile_id
    where profile.auth_user_id = '44444444-4444-4444-4444-444444444444'
  ) then raise exception 'technician received a new IAM role'; end if;
end $$
""", "select public.bootstrap_legacy_practitioner_iam()", "select public.bootstrap_synthetic_hospitalization_fixtures()", """do $$ begin
  if (select count(*) from public.profiles) <> 5 then raise exception 'bridge retry duplicated profiles'; end if;
  if (select count(*) from public.organization_memberships) <> 5 then raise exception 'bridge retry duplicated memberships'; end if;
  if (select count(*) from public.role_assignments) <> 3 then raise exception 'bridge retry duplicated role grants'; end if;
end $$
""", """do $$ begin
  if (select count(*) from public.hospitalizations where patient_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') <> 2 then raise exception 'explicit synthetic episodes were not backfilled'; end if;
  if (select count(*) from public.hospitalization_locations l join public.hospitalizations h on h.id=l.hospitalization_id where h.patient_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') <> 2 then raise exception 'fixture bridge retry duplicated locations'; end if;
  if (select count(*) from public.clinical_events where hospitalization_id is not null) <> 4 then raise exception 'explicit synthetic events were not mapped'; end if;
  if (select organization_id from public.patients where id='90000000-0000-0000-0000-000000000001') is not null then raise exception 'unknown patient was published'; end if;
  if (select organization_id from public.clinical_events where id='90000000-0000-0000-0000-000000000002') is not null or (select hospitalization_id from public.clinical_events where id='90000000-0000-0000-0000-000000000002') is not null then raise exception 'unknown event was published'; end if;
   if (select count(*) from public.care_assignments assignment
       join public.organization_memberships membership on membership.id=assignment.membership_id
       join public.profiles profile on profile.id=membership.profile_id
       where profile.auth_user_id='11111111-1111-1111-1111-111111111111') <> 2 then raise exception 'Ana should receive only the two explicit Elena assignments'; end if;
  if not exists (select 1 from pg_constraint where conname='clinical_events_episode_patient_tenant_fk' and contype='f') then raise exception 'event-to-episode patient/tenant FK missing'; end if;
  if not exists (select 1 from pg_constraint where conname='hospitalization_locations_no_overlapping_periods' and contype='x') then raise exception 'location exclusion constraint missing'; end if;
   if not exists (select 1 from pg_constraint where conname='care_assignments_no_overlapping_live_assignments' and contype='x') then raise exception 'care-assignment exclusion constraint missing'; end if;
   if not has_function_privilege('authenticated', 'public.grant_care_assignment(uuid,uuid,uuid,timestamptz,timestamptz,uuid)', 'execute') then raise exception 'authenticated grant RPC missing'; end if;
   if has_function_privilege('service_role', 'public.grant_care_assignment(uuid,uuid,uuid,timestamptz,timestamptz,uuid)', 'execute') then raise exception 'service_role must not invoke assignment RPC'; end if;
   if not exists (
     select 1 from pg_proc p
     cross join lateral unnest(p.proconfig) as cfg(value)
     where p.oid='private.care_assignment_operation(text,uuid,uuid,uuid,timestamptz,timestamptz,uuid,uuid)'::regprocedure
       and pg_catalog.lower(cfg.value)='timezone=utc'
   ) then raise exception 'care-assignment idempotency timezone is not canonical UTC'; end if;
   if not exists (
     select 1 from pg_proc p
     where p.oid='private.care_assignment_operation(text,uuid,uuid,uuid,timestamptz,timestamptz,uuid,uuid)'::regprocedure
       and pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(p.oid)), 'has_active_iam_permission') > 0
       and pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(p.oid)), 'select * into prior') > 0
       and pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(p.oid)), 'has_active_iam_permission')
         < pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(p.oid)), 'select * into prior')
   ) then raise exception 'replay lookup is not ordered after the effective permission check'; end if;
   if not exists (
     select 1 from pg_policies policy
     where policy.schemaname='public' and policy.tablename='units'
       and policy.policyname='authorized members read units'
       and policy.qual like '%has_active_iam_permission%org.unit.read%'
   ) then raise exception 'units SELECT policy does not require org.unit.read'; end if;
   if exists (
     select 1 from public.role_permissions rp
     join public.roles role on role.id=rp.role_id and role.organization_id=rp.organization_id
     where role.organization_id=(select id from public.organizations where slug='demo-hospital')
       and rp.permission_code='org.unit.read' and role.protected_kind is distinct from 'demo_administrator'
   ) then raise exception 'org.unit.read was granted to a non-administrator role'; end if;
    if has_table_privilege('service_role', 'public.care_assignments', 'truncate')
      or has_table_privilege('service_role', 'public.care_assignments', 'insert')
      or has_table_privilege('service_role', 'public.care_assignments', 'update')
       or has_table_privilege('service_role', 'public.care_assignments', 'delete') then raise exception 'service_role retains care-assignment write privilege'; end if;
     if exists (
       select 1 from unnest(array['authenticated','service_role']) runtime_role
       cross join unnest(array['public.patients','public.clinical_events']) clinical_table
       cross join unnest(array['insert','update','delete','truncate']) action
       where has_table_privilege(runtime_role, clinical_table, action)
     ) then raise exception 'runtime role retains clinical DML privilege'; end if;
     if exists (
       select 1 from unnest(array['authenticated','service_role']) runtime_role
       cross join unnest(array['public.organization_memberships','public.roles','public.role_permissions','public.role_assignments']) iam_table
       cross join unnest(array['insert','update','delete','truncate']) action
       where has_table_privilege(runtime_role, iam_table, action)
     ) then raise exception 'runtime role retains IAM DML privilege'; end if;
     if not has_function_privilege('authenticated','public.manage_organization_membership(uuid,uuid,text,timestamptz,uuid)','execute')
       or has_function_privilege('service_role','public.manage_organization_membership(uuid,uuid,text,timestamptz,uuid)','execute')
       then raise exception 'IAM RPC execution is not authenticated-only'; end if;
     if not exists (select 1 from pg_constraint where conname='role_assignments_no_overlapping_equivalent_grants' and contype='x')
       then raise exception 'live role-assignment exclusion constraint missing'; end if;
     if pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.iam_admin_operation(text,uuid,uuid,text,timestamptz,timestamptz,text[],uuid)'::regprocedure),'role_not_delegable')=0
       or pg_catalog.strpos(pg_catalog.pg_get_functiondef('private.iam_admin_operation(text,uuid,uuid,text,timestamptz,timestamptz,text[],uuid)'::regprocedure),'self_revocation_denied')=0
       then raise exception 'phase 4.1 delegation/self-revocation protections missing'; end if;
     if pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.create_iam_role(uuid,text,text,uuid)'::regprocedure),'jsonb_build_array')=0
       or pg_catalog.strpos(pg_catalog.pg_get_functiondef('public.update_iam_role(uuid,uuid,text,text,uuid)'::regprocedure),'jsonb_build_array')=0
       then raise exception 'role fields are not transported as an unambiguous JSON array'; end if;
     if (select count(*) from public.role_permissions rp join public.roles r on r.id=rp.role_id
       where r.protected_kind='demo_administrator' and rp.permission_code='clinical.assigned.read')<>1
       then raise exception 'protected administrator assigned-read composition missing or duplicated'; end if;
      if (select count(*) from public.role_permissions rp join public.roles r on r.id=rp.role_id
        where r.protected_kind='demo_administrator' and rp.permission_code='clinical.assigned.read')<>1
        then raise exception 'protected assigned-read migration is not idempotent'; end if;
      if not has_function_privilege('authenticated','public.register_organization_member(uuid,uuid,text,text,uuid,uuid)','execute')
        or has_function_privilege('service_role','public.register_organization_member(uuid,uuid,text,text,uuid,uuid)','execute')
        then raise exception 'member registration RPC execution is not authenticated-only'; end if;
      if exists (select 1 from unnest(array['authenticated','service_role']) runtime_role
        cross join unnest(array['insert','update','delete','truncate']) action
        where has_table_privilege(runtime_role,'public.profiles',action))
        then raise exception 'runtime profile DML grants remain'; end if;
    if (select array_agg(column_name order by ordinal_position)::text
        from information_schema.columns where table_schema='public'
          and table_name='clinical_census_by_hospitalization') <>
      '{organization_id,hospitalization_id,patient_id,hospitalization_status,admitted_at,discharged_at,unit_id,bed_label,given_name,family_name,birth_date}'
      then raise exception 'clinical census column contract mismatch'; end if;
    if (select array_agg(column_name order by ordinal_position)::text
        from information_schema.columns where table_schema='public'
          and table_name='clinical_timeline_by_hospitalization') <>
      '{organization_id,hospitalization_id,event_id,kind,occurred_at,summary,patient_id,created_at,source_kind,author_display_name}'
      then raise exception 'clinical timeline column contract mismatch'; end if;
    if has_column_privilege('authenticated','public.clinical_events','payload','select')
       or has_column_privilege('authenticated','public.clinical_events','recorded_by','select')
      then raise exception 'clinical timeline exposes sensitive columns'; end if;
    if not exists (select 1 from pg_trigger where tgname='patients_runtime_dml_guard' and not tgisinternal)
       or not exists (select 1 from pg_trigger where tgname='clinical_events_runtime_dml_guard' and not tgisinternal)
      then raise exception 'clinical runtime DML guards are missing'; end if;
   if not exists (select 1 from public.role_permissions rp join public.roles r on r.id=rp.role_id where r.protected_kind='demo_administrator' and rp.permission_code='audit.read') then raise exception 'audit.read missing from protected demo administrator'; end if;
  begin
    update public.clinical_events set hospitalization_id='a1000000-0000-0000-0000-000000000003' where id='cccccccc-cccc-cccc-cccc-cccccccccccc';
    raise exception 'patient mismatch unexpectedly accepted';
  exception when foreign_key_violation then null;
  end;
  begin
    update public.clinical_events set organization_id=null where id='cccccccc-cccc-cccc-cccc-cccccccccccc';
    raise exception 'partial event link unexpectedly accepted';
  exception when check_violation then null;
  end;
end $$
"""]
        for statement in checks:
            run_sql(container, statement)
        run_sql(container, """
create function public.upgrade_test_clinical_bridge()
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.clinical_events set summary=summary
   where id='cccccccc-cccc-cccc-cccc-cccccccccccc';
end $$;
grant execute on function public.upgrade_test_clinical_bridge() to service_role;
set role service_role;
select public.upgrade_test_clinical_bridge();
reset role;
drop function public.upgrade_test_clinical_bridge();
""")
        print("PASS: isolated baseline-to-phase-4.3 upgrade, IAM/clinical write guards, and explicit synthetic backfill")
    finally:
        if started:
            subprocess.run(
                [*supabase, "stop", "--workdir", str(project), "--no-backup", "--yes"],
                cwd=ROOT, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT,
            )
        shutil.rmtree(temporary, ignore_errors=True)


if __name__ == "__main__":
    main()
