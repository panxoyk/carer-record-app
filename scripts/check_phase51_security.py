#!/usr/bin/env python3
"""Print redacted local PostgreSQL security checks and selective EXPLAIN plans.

Requires a running, reset Supabase local project. Database credentials are read
from `supabase status` at runtime and are never printed.
"""

import json
import pathlib
import re
import subprocess
import sys


def run_sql(sql: str) -> str:
    result = subprocess.run(
        ["pnpm", "exec", "supabase", "db", "query", "--local",
         "--output-format", "json", sql],
        check=True, capture_output=True, text=True,
    )
    start = result.stdout.find("{")
    if start < 0:
        raise RuntimeError("Supabase CLI returned no structured query result")
    rows = json.JSONDecoder().raw_decode(result.stdout[start:])[0]["rows"]
    return "\n".join(str(next(iter(row.values()))) for row in rows)


def versioned_secret_candidates() -> bool:
    files = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard"],
        check=True, capture_output=True, text=True,
    ).stdout.splitlines()
    patterns = (
        re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"),
        re.compile(r"sb_secret_[A-Za-z0-9_-]{12,}"),
        re.compile(r"SUPABASE_SERVICE_ROLE_KEY\s*=\s*[^$\s\"'][^\s\"']*"),
    )
    for name in files:
        try:
            content = pathlib.Path(name).read_text(errors="ignore")
        except OSError:
            continue
        if any(pattern.search(content) for pattern in patterns):
            return True
    return False


def main() -> None:
    subprocess.run(
        ["pnpm", "exec", "supabase", "status", "-o", "env"],
        check=True, capture_output=True, text=True,
    )

    checks = {
        "clinical legacy policies/helpers absent": """
          select (not exists (select 1 from pg_policies where schemaname='public'
            and tablename in ('patients','clinical_events')
            and policyname in ('active care roles read patients','active care roles read clinical events'))
            and to_regprocedure('public.can_read_patients()') is null
            and to_regprocedure('public.can_read_clinical_events()') is null)::int
        """,
        "security-definer functions have empty search_path": """
          select coalesce(bool_and(proconfig @> array['search_path=""']), true)::int
          from pg_proc p join pg_namespace n on n.oid=p.pronamespace
          where n.nspname in ('public','private') and p.prosecdef
        """,
        "runtime has no clinical DML/TRUNCATE grants": """
          select bool_and(not has_table_privilege(r, t, a))::int
          from unnest(array['authenticated','service_role']) r
          cross join unnest(array['public.patients','public.clinical_events']) t
          cross join unnest(array['insert','update','delete','truncate']) a
        """,
        "audit append-only trigger installed": """
          select (exists (select 1 from pg_trigger where tgrelid='public.audit_events'::regclass
            and tgname='audit_events_append_only' and not tgisinternal))::int
        """,
        "clinical views invoker + barrier": """
          select (count(*)=3 and bool_and(reloptions @> array['security_invoker=true','security_barrier=true']))::int
          from pg_class where oid in ('public.clinical_census_by_hospitalization'::regclass,
            'public.clinical_patient_demographics_by_hospitalization'::regclass,
            'public.clinical_timeline_by_hospitalization'::regclass)
        """,
        "assignment RPC EXECUTE is authenticated-only": """
          select (has_function_privilege('authenticated','public.grant_care_assignment(uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,uuid)','execute')
            and has_function_privilege('authenticated','public.revoke_care_assignment(uuid,uuid,uuid)','execute')
            and not has_function_privilege('anon','public.grant_care_assignment(uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,uuid)','execute')
            and not has_function_privilege('service_role','public.grant_care_assignment(uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,uuid)','execute'))::int
        """,
        "technician has no IAM role assignment or care assignment": """
          select ((select count(*) from public.role_assignments ra
            join public.organization_memberships m on m.id=ra.membership_id
            join public.profiles p on p.id=m.profile_id where p.auth_user_id='44444444-4444-4444-4444-444444444444') = 0
            and (select count(*) from public.care_assignments ca
            join public.organization_memberships m on m.id=ca.membership_id
            join public.profiles p on p.id=m.profile_id where p.auth_user_id='44444444-4444-4444-4444-444444444444') = 0)::int
        """,
        "critical indexes exist": """
          select (count(distinct indexrelid)=8)::int from pg_index i
          join pg_class t on t.oid=i.indrelid join pg_class x on x.oid=i.indexrelid
          where (t.relname,x.relname) in (
            ('hospitalizations','hospitalizations_pkey'),
            ('organization_memberships','organization_memberships_pkey'),
            ('role_assignments','role_assignments_effective_membership_idx'),
            ('role_permissions','role_permissions_pkey'),
            ('care_assignments','care_assignments_episode_idx'),
            ('care_assignments','care_assignments_membership_validity_idx'),
            ('clinical_events','clinical_events_episode_timeline_idx'),
            ('profiles','profiles_auth_user_id_key'))
        """,
        "no role-enum or role-name authority in current clinical policies": """
          select (not exists (select 1 from pg_policies where schemaname='public'
            and tablename in ('patients','clinical_events')
            and (qual ilike '%practitioner_role%' or qual ilike '%technician%'
              or qual ilike '%physician%' or qual ilike '%nurse%' or qual ilike '%administrator%'))
            and to_regprocedure('public.can_read_patients()') is null)::int
        """,
    }
    failed = []
    has_secret = versioned_secret_candidates()
    print(f"{'FAIL' if has_secret else 'PASS'} no literal service key/JWT candidates in working-tree files")
    if has_secret:
        failed.append("versioned secret scan")
    for label, sql in checks.items():
        value = run_sql(sql)
        ok = value == "1"
        print(f"{'PASS' if ok else 'FAIL'} {label}")
        if not ok:
            failed.append(label)

    plans = [
        ("hospitalization lookup by organization + episode (planner/indexability only; not an RLS runtime test)", """
          explain select id from public.hospitalizations
          where organization_id='00000000-0000-0000-0000-000000000000'
            and id='a1000000-0000-0000-0000-000000000001'
        """),
        ("membership by organization + membership", """
          explain select id from public.organization_memberships
          where organization_id='00000000-0000-0000-0000-000000000000'
            and id='b1000000-0000-0000-0000-000000000001'
        """),
        ("role assignments by organization + membership", """
          explain select id from public.role_assignments
          where organization_id='00000000-0000-0000-0000-000000000000'
            and membership_id='b1000000-0000-0000-0000-000000000001'
            and revoked_at is null
        """),
        ("care assignments by organization + hospitalization + membership", """
          explain select id from public.care_assignments
          where organization_id='00000000-0000-0000-0000-000000000000'
            and hospitalization_id='a1000000-0000-0000-0000-000000000001'
            and membership_id='b1000000-0000-0000-0000-000000000001'
            and revoked_at is null
        """),
    ]
    print("EXPLAIN (estimates only; no ANALYZE, fixture-independent):")
    for label, sql in plans:
        print(f"[{label}]")
        print(run_sql(sql))
    print("Plan criterion: selective predicates should be indexable; a seq scan on tiny seed tables is acceptable. Do not force indexes based on seed cardinality.")
    if failed:
        raise RuntimeError(f"security evidence failed ({len(failed)} check(s)); inspect source/tests")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"Phase 5.1 security evidence failed: {error}", file=sys.stderr)
        sys.exit(1)
