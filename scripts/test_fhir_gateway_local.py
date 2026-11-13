#!/usr/bin/env python3
"""Non-destructive HTTP integration check for the local FHIR clinical gateway.

Uses only deterministic demo fixtures. It never resets Supabase, writes clinical
rows, or deletes fixture/history data.
"""

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def request(method, url, key=None, token=None, body=None, timeout=10):
    headers = {}
    if key:
        headers["apikey"] = key
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if body is not None:
        headers["Content-Type"] = "application/json"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            raw = response.read().decode()
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        return error.code, None


def fhir_uuid(resource_type, identifier):
    # Use the canonical deterministic ID function rather than duplicating it.
    result = subprocess.run(
        ["node", "--input-type=module", "-e",
         'import {uuidFor} from "./scripts/fhir-sync/generate-sync.mjs"; '
         'console.log(uuidFor("demo-hospital\\0demo-hapi", process.argv[1], process.argv[2]))',
         resource_type, identifier], check=True, capture_output=True, text=True,
    )
    return result.stdout.strip()


def main():
    status = subprocess.run(["pnpm", "exec", "supabase", "status", "-o", "env"],
                           check=True, capture_output=True, text=True).stdout
    env = {}
    for line in status.splitlines():
        if "=" in line:
            name, value = line.split("=", 1)
            env[name] = value.strip().strip('"').strip("'")
    base = os.environ.get("SUPABASE_LOCAL_URL", "http://127.0.0.1:54321").rstrip("/")
    require(urllib.parse.urlparse(base).hostname in ("127.0.0.1", "localhost", "::1"),
            "refusing non-local Supabase URL")
    anon = env.get("ANON_KEY") or env.get("PUBLISHABLE_KEY")
    service = env.get("SERVICE_ROLE_KEY")
    require(anon and service, "local Supabase credentials unavailable")
    gateway = os.environ.get("FHIR_GATEWAY_URL", base + "/functions/v1/clinical-record").rstrip("/")

    def login(email):
        code, result = request("POST", f"{base}/auth/v1/token?grant_type=password", anon,
                               body={"email": email, "password": "ChangeMe123!"})
        require(code == 200 and result and result.get("access_token"), "demo fixture login failed")
        return result["access_token"]

    ana = login("ana.torres@example.test")
    matias = login("matias.rojas@example.test")
    # Derive organization from the authenticated caller's IAM RPC; no credential is printed.
    code, context = request("GET", f"{base}/rest/v1/iam_current_context?select=organization_id",
                            anon, ana)
    require(code == 200 and context, "demo organization context unavailable")
    organization = context[0]["organization_id"]
    assignment_manifest = json.load(open("scripts/fhir-sync/demo-assignments.json", encoding="utf-8"))
    actor_ids = {
        "ana.torres@example.test": "11111111-1111-1111-1111-111111111111",
        "matias.rojas@example.test": "22222222-2222-2222-2222-222222222222",
    }
    expected = {
        email: [row["fhirId"] for row in assignment_manifest["encounters"]
                if row["authUserId"] == actor_id and not row.get("validUntil")]
        for email, actor_id in actor_ids.items()
    }

    def check_gateway(token, encounter, purpose=None):
        body = {"organizationId": organization,
                "hospitalizationId": fhir_uuid("Encounter", encounter)}
        if purpose:
            body["purpose"] = purpose
        return request("POST", gateway, anon, token, body)

    # Brief bounded retry for Edge runtime startup; never dump upstream bodies/logs.
    deadline = time.monotonic() + 5
    ready = False
    last_code = None
    while time.monotonic() < deadline:
        try:
            code, _ = check_gateway(ana, expected["ana.torres@example.test"][0])
            last_code = code
            ready = code != 502 and code != 503
            if ready:
                break
        except OSError:
            pass
        time.sleep(0.5)
    require(ready, f"clinical-record returned HTTP {last_code}; verify HAPI is running and attached to supabase_network_carer-record as hapi-fhir")

    for token, encounters in ((ana, expected["ana.torres@example.test"]),
                              (matias, expected["matias.rojas@example.test"])):
        for encounter in encounters:
            code, dto = check_gateway(token, encounter)
            require(code == 200 and isinstance(dto, dict), "authorized record request failed")
            require(dto.get("timeline") == [], "record purpose exposed timeline")
    code, _ = check_gateway(ana, "enc-surg-matias")
    require(code == 404, "foreign episode was not denied")
    code, _ = request("POST", gateway, anon, body={"organizationId": organization,
                           "hospitalizationId": fhir_uuid("Encounter", "enc-med-ana")})
    require(code == 401, "anonymous gateway request was not rejected")
    code, _ = request("POST", gateway, anon, service, {"organizationId": organization,
                           "hospitalizationId": fhir_uuid("Encounter", "enc-med-ana")})
    require(code == 401, "service role was accepted as a user JWT")
    for actor, token, encounters in (("Ana", ana, expected["ana.torres@example.test"]),
                                      ("Matías", matias, expected["matias.rojas@example.test"])):
        for encounter in encounters:
            code, dto = check_gateway(token, encounter, "timeline")
            timeline = dto.get("timeline", []) if isinstance(dto, dict) else []
            require(code == 200 and timeline, f"{actor} timeline unavailable")
            if encounter in ("enc-med-ana", "enc-shared"):
                require(any(event.get("resourceType") == "Observation" for event in timeline),
                        f"{actor} timeline omitted observations/labs for {encounter}")

    # Census view is separately protected by RLS. Only linked fixture episodes appear.
    for token, own, other in ((ana, expected["ana.torres@example.test"], expected["matias.rojas@example.test"]),
                              (matias, expected["matias.rojas@example.test"], expected["ana.torres@example.test"])):
        code, rows = request("GET", f"{base}/rest/v1/fhir_clinical_census_by_hospitalization?select=hospitalization_id",
                             anon, token)
        require(code == 200 and isinstance(rows, list), "FHIR clinical census view unavailable")
        ids = {row["hospitalization_id"] for row in rows}
        expected_ids = {fhir_uuid("Encounter", item) for item in own}
        foreign_only = {fhir_uuid("Encounter", item) for item in other} - expected_ids
        require(ids == expected_ids,
                "census episode set differs from the actor's manifest-assigned fixtures")
        require(not (foreign_only & ids),
                "census exposed a foreign demo encounter")
    print("FHIR gateway local HTTP integration passed (synthetic fixtures; credentials redacted).")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"FHIR gateway integration failed: {error}", file=sys.stderr)
        sys.exit(1)
