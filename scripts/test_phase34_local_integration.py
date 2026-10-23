#!/usr/bin/env python3
"""Real local integration gate. DESTRUCTIVE: resets only disposable local
Supabase synthetic state before and after each run. Never use on linked or
production projects. Reset is required because audit/history is append-only;
rows are never deleted manually. Secrets and response bodies stay in memory.
"""

import json
import os
import signal
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timezone


def request(method, url, key, token=None, body=None, prefer=None):
    headers = {"apikey": key}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if body is not None:
        headers["Content-Type"] = "application/json"
    if prefer:
        headers["Prefer"] = prefer
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            text = response.read().decode()
            return response.status, json.loads(text) if text else None
    except urllib.error.HTTPError as error:
        # Do not surface server messages: they may contain user-supplied values.
        return error.code, None


def require(condition, label):
    if not condition:
        raise RuntimeError(label)


def edge_available(base, anon, token):
    try:
        code, _ = request("GET", f"{base}/functions/v1/create-practitioner", anon, token)
        return code == 405
    except (OSError, TimeoutError):
        return False


def start_edge_if_needed(base, anon, token):
    if edge_available(base, anon, token):
        return None
    process = subprocess.Popen(
        ["pnpm", "exec", "supabase", "functions", "serve"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        # Give the local runtime a bounded interval to initialize.
        import time
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError("local Edge runtime failed to start")
            if edge_available(base, anon, token):
                return process
            time.sleep(0.5)
        raise RuntimeError("local Edge runtime did not become available")
    except Exception:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        raise


def stop_edge(process):
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()


def integration():
    status = subprocess.run(
        ["pnpm", "exec", "supabase", "status", "-o", "env"],
        check=True, capture_output=True, text=True,
    ).stdout
    env = dict(
        (key, value.strip().strip('"')) for line in status.splitlines()
        if "=" in line and line.split("=", 1)[0].isidentifier()
        for key, value in [line.split("=", 1)]
    )
    base = os.environ.get("SUPABASE_LOCAL_URL", "http://127.0.0.1:54321")
    require(urllib.parse.urlparse(base).hostname in ("127.0.0.1", "localhost", "::1"),
            "refusing integration against a non-local Supabase URL")
    anon = env.get("ANON_KEY") or env.get("PUBLISHABLE_KEY")
    service_role = env.get("SERVICE_ROLE_KEY")
    require(bool(anon), "local Supabase is not running; start it and reset first")
    require(bool(service_role), "local service role key unavailable")

    def login(email):
        code, result = request("POST", f"{base}/auth/v1/token?grant_type=password", anon,
                               body={"email": email, "password": "ChangeMe123!"})
        require(code == 200 and result and result.get("access_token"), "synthetic actor login failed")
        return result["access_token"]

    admin = login("admin@example.test")
    clinician = login("matias.rojas@example.test")
    code, admin_context = request(
        "GET", f"{base}/rest/v1/iam_current_context?select=organization_id,membership_id,permission_code",
        anon, admin,
    )
    require(code == 200 and admin_context, "synthetic administrator IAM context missing")
    admin_row = next((row for row in admin_context if row.get("permission_code") == "clinical.assignment.manage"), None)
    require(admin_row is not None, "synthetic administrator assignment permission missing")
    org = admin_row["organization_id"]
    clinician_query = urllib.parse.urlencode({"select": "membership_id,display_name", "organization_id": f"eq.{org}"})
    code, members = request("GET", f"{base}/rest/v1/iam_member_directory?{clinician_query}", anon, admin)
    require(code == 200, "synthetic member directory unavailable")
    clinician_row = next((row for row in members if row.get("display_name") == "Matías Rojas"), None)
    require(clinician_row is not None, "synthetic clinician membership missing")
    role_query = urllib.parse.urlencode({
        "select": "role_id", "organization_id": f"eq.{org}", "protected_kind": "is.null",
        "role_status": "eq.active", "limit": "1",
    })
    code, roles = request("GET", f"{base}/rest/v1/iam_role_directory?{role_query}", anon, admin)
    require(code == 200 and roles, "ordinary synthetic role missing")
    clinician_member, role_id = clinician_row["membership_id"], roles[0]["role_id"]
    key = str(uuid.uuid4())
    assignment_id = None
    edge_process = None
    try:
        body = {
            "p_organization_id": org,
            "p_hospitalization_id": "a1000000-0000-0000-0000-000000000001",
            "p_membership_id": clinician_member,
            "p_valid_from": datetime.now(timezone.utc).isoformat(),
            "p_valid_until": None,
            "p_idempotency_key": key,
        }
        code, rows = request("POST", f"{base}/rest/v1/rpc/grant_care_assignment", anon, admin, body)
        require(code == 200 and rows and rows[0].get("result_code") == "granted", "care grant RPC failed")
        assignment_id = rows[0]["assignment_id"]

        view = "clinical_census_by_hospitalization"
        query = urllib.parse.urlencode({
            "select": "hospitalization_id,patient_id,given_name,family_name,birth_date",
            "organization_id": f"eq.{org}",
            "hospitalization_id": "eq.a1000000-0000-0000-0000-000000000001",
        })
        code, rows = request("GET", f"{base}/rest/v1/{view}?{query}", anon, clinician)
        require(code == 200 and rows, "clinical view did not expose assigned synthetic episode")
        require(all({"given_name", "family_name", "birth_date"} <= row.keys() for row in rows),
                "assigned episode demographics contract missing")

        demographics_view = "clinical_patient_demographics_by_hospitalization"
        demographics_query = urllib.parse.urlencode({
            "select": "organization_id,hospitalization_id,patient_id,given_name,family_name,birth_date",
            "organization_id": f"eq.{org}",
            "hospitalization_id": "eq.a1000000-0000-0000-0000-000000000001",
        })
        code, demographics = request(
            "GET", f"{base}/rest/v1/{demographics_view}?{demographics_query}", anon, clinician,
        )
        require(code == 200 and demographics and all({
            "organization_id", "hospitalization_id", "patient_id", "given_name", "family_name", "birth_date",
        } <= row.keys() and row["organization_id"] == org
            and row["hospitalization_id"] == "a1000000-0000-0000-0000-000000000001"
            for row in demographics),
                "assigned episode demographics view did not expose its explicit contract")

        timeline_query = urllib.parse.urlencode({
            "select": "hospitalization_id,event_id,kind,occurred_at,summary,patient_id,created_at,source_kind,author_display_name",
            "organization_id": f"eq.{org}",
            "hospitalization_id": "eq.a1000000-0000-0000-0000-000000000001",
        })
        code, timeline = request(
            "GET", f"{base}/rest/v1/clinical_timeline_by_hospitalization?{timeline_query}",
            anon, clinician,
        )
        require(code == 200 and timeline, "assigned episode timeline unavailable")
        require(all("payload" not in row and "recorded_by" not in row for row in timeline),
                "timeline exposed a private field")

        changed = query.replace("a1000000-0000-0000-0000-000000000001",
                                "a1000000-0000-0000-0000-000000000009")
        code, rows = request("GET", f"{base}/rest/v1/{view}?{changed}", anon, clinician)
        require(code == 200 and rows == [], "manipulated hospitalization UUID exposed rows")
        changed_demographics = demographics_query.replace(
            "a1000000-0000-0000-0000-000000000001",
            "a1000000-0000-0000-0000-000000000009",
        )
        code, rows = request(
            "GET", f"{base}/rest/v1/{demographics_view}?{changed_demographics}", anon, clinician,
        )
        require(code == 200 and rows == [], "manipulated hospitalization UUID exposed demographics")

        # Exercise Edge method handling and authenticated authorization denial.
        edge_process = start_edge_if_needed(base, anon, clinician)
        code, _ = request("GET", f"{base}/functions/v1/create-practitioner", anon, clinician)
        require(code == 405, "create-practitioner method guard failed")
        edge_body = {
            "organizationId": org, "email": "synthetic.integration@example.test",
            "password": "Synthetic-Integration-Password-42", "displayName": "Synthetic integration",
            "roleId": role_id, "idempotencyKey": str(uuid.uuid4()),
        }
        code, _ = request("POST", f"{base}/functions/v1/create-practitioner", anon, clinician, edge_body)
        require(code == 403, "create-practitioner did not deny authenticated clinician")
        code, _ = request("POST", f"{base}/functions/v1/create-practitioner", anon, clinician,
                          {"invalid": "synthetic"})
        require(code == 400, "create-practitioner did not distinguish invalid payload from denied privilege")

        # The service-role credential is never accepted as an authenticated
        # human caller, even though its key is used below for aggregate checks.
        service_body = dict(edge_body, email=f"synthetic-{uuid.uuid4()}@example.test",
                            idempotencyKey=str(uuid.uuid4()))
        code, _ = request("POST", f"{base}/functions/v1/create-practitioner",
                          anon, service_role, service_body)
        require(code in (401, 403), "service role unexpectedly authorized as Edge caller")

        # Real Edge + Auth success, idempotent replay, and stable conflict.
        edge_key = str(uuid.uuid4())
        edge_email = f"synthetic-{uuid.uuid4()}@example.test"
        registration = {
            "organizationId": org, "email": edge_email,
            "password": f"Synthetic-{uuid.uuid4()}-Password-42",
            "displayName": "Synthetic phase gate", "roleId": role_id,
            "idempotencyKey": edge_key,
        }
        code, _ = request("POST", f"{base}/functions/v1/create-practitioner", anon, admin, registration)
        require(code == 201, "real Edge registration did not return 201")
        code, _ = request("POST", f"{base}/functions/v1/create-practitioner", anon, admin, registration)
        require(code == 200, "same-key same-payload Edge replay did not return 200")
        code, _ = request("POST", f"{base}/functions/v1/create-practitioner", anon, admin,
                          dict(registration, displayName="Different synthetic display name"))
        require(code == 409, "same-key different-payload Edge request did not return 409")

        auth_code, auth_users = request(
            "GET", f"{base}/auth/v1/admin/users?page=1&per_page=1000", service_role, service_role
        )
        require(auth_code == 200 and isinstance(auth_users, dict),
                f"local Auth aggregate inspection failed (HTTP {auth_code}, response type {type(auth_users).__name__})")
        users = [u for u in auth_users.get("users", []) if u.get("email") == edge_email]
        require(len(users) == 1, "Edge replay created a duplicate Auth user")
        profile_query = urllib.parse.urlencode({"select": "id", "auth_user_id": f"eq.{users[0]['id']}"})
        code, profiles = request("GET", f"{base}/rest/v1/profiles?{profile_query}", service_role, service_role)
        require(code == 200 and len(profiles or []) == 1, "Edge replay created duplicate/missing profile")
        membership_query = urllib.parse.urlencode({"select": "id", "profile_id": f"eq.{profiles[0]['id']}"})
        code, memberships = request(
            "GET", f"{base}/rest/v1/organization_memberships?{membership_query}", service_role, service_role
        )
        require(code == 200 and len(memberships or []) == 1,
                "Edge replay created duplicate/missing organization membership")
        grant_query = urllib.parse.urlencode({"select": "id", "membership_id": f"eq.{memberships[0]['id']}"})
        code, grants = request("GET", f"{base}/rest/v1/role_assignments?{grant_query}", service_role, service_role)
        require(code == 200 and len(grants or []) == 1,
                "Edge replay created duplicate/missing role grant")

        code, _ = request("POST", f"{base}/rest/v1/patients", anon, admin,
                          {"given_name": "Synthetic", "family_name": "Denied"})
        require(code in (401, 403), "direct clinical DML was not denied")

        code, rows = request("POST", f"{base}/rest/v1/rpc/revoke_care_assignment", anon, admin,
                             {"p_organization_id": org, "p_assignment_id": assignment_id,
                              "p_idempotency_key": str(uuid.uuid4())})
        require(code == 200 and rows and rows[0].get("result_code") == "revoked", "care revoke RPC failed")
        code, rows = request("GET", f"{base}/rest/v1/{view}?{query}", anon, clinician)
        require(code == 200 and rows == [], "revoked clinician retained clinical rows")
        code, rows = request(
            "GET", f"{base}/rest/v1/{demographics_view}?{demographics_query}", anon, clinician,
        )
        require(code == 200 and rows == [], "revoked clinician retained demographic view rows")
        code, rows = request(
            "GET", f"{base}/rest/v1/clinical_timeline_by_hospitalization?{timeline_query}",
            anon, clinician,
        )
        require(code == 200 and rows == [], "revoked clinician retained timeline rows")
    finally:
        if assignment_id:
            request("POST", f"{base}/rest/v1/rpc/revoke_care_assignment", anon, admin,
                    {"p_organization_id": org, "p_assignment_id": assignment_id,
                     "p_idempotency_key": str(uuid.uuid4())})
        if edge_process is not None:
            stop_edge(edge_process)
    print("Local phase 3+4 integration passed (synthetic fixtures; credentials and payloads redacted).")


if __name__ == "__main__":
    # Reset only the local disposable synthetic project. This deliberately
    # destroys local test history and audit rows, never production/linked data.
    subprocess.run(["pnpm", "db:reset"], check=True, capture_output=True, text=True)
    succeeded = False
    try:
        integration()
        succeeded = True
    except Exception as error:
        print(f"Local phase 3+4 integration failed: {error}", file=sys.stderr)
    finally:
        cleanup = subprocess.run(["pnpm", "db:reset"], capture_output=True, text=True)
        if cleanup.returncode:
            print("Local Supabase cleanup reset failed; clean baseline is not guaranteed.", file=sys.stderr)
            sys.exit(1)
    if not succeeded:
        sys.exit(1)
