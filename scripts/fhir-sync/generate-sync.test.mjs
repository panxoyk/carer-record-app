import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { mapResources, renderSql, uuidFor } from "./generate-sync.mjs";

const fixture = () => ({
  patients: [
    {
      resourceType: "Patient",
      id: "person-alpha",
      name: [{ given: ["Ana"], family: "Demo" }],
    },
  ],
  locations: [
    {
      resourceType: "Location",
      id: "room-a",
      name: "Sala A",
      physicalType: { coding: [{ code: "wa" }] },
    },
    {
      resourceType: "Location",
      id: "bed-a",
      name: "Cama 1",
      partOf: { reference: "Location/room-a" },
      physicalType: { coding: [{ code: "bd" }] },
    },
  ],
  encounters: [
    {
      resourceType: "Encounter",
      id: "episode-alpha",
      status: "in-progress",
      class: { code: "IMP" },
      subject: { reference: "Patient/person-alpha" },
      period: { start: "2026-10-20T10:00:00Z" },
      location: [
        {
          location: { reference: "Location/bed-a", display: "1" },
          period: { start: "2026-10-20T10:00:00Z" },
        },
      ],
    },
  ],
});

test("identity is deterministic by tenant, resource type and opaque FHIR id", () => {
  assert.equal(
    uuidFor("tenant", "Patient", "abc"),
    uuidFor("tenant", "Patient", "abc"),
  );
  assert.notEqual(
    uuidFor("tenant", "Patient", "abc"),
    uuidFor("tenant", "Encounter", "abc"),
  );
  assert.notEqual(
    uuidFor("tenant", "Patient", "abc"),
    uuidFor("other", "Patient", "abc"),
  );
});
test("maps episode and stable patient identity with open location", () => {
  const model = mapResources(fixture());
  assert.equal(model.patients[0].fhirId, "person-alpha");
  assert.equal(
    model.encounters[0].id,
    uuidFor("demo-hospital\0demo-hapi", "Encounter", "episode-alpha"),
  );
  assert.equal(model.encounters[0].locations[0].ended_at, null);
  assert.equal(
    model.locations.find((x) => x.fhirId === "bed-a").unit_name,
    "Sala A",
  );
});
test("rejects mismatched/missing references, invalid state and dates", () => {
  const bad = fixture();
  bad.encounters[0].subject.reference = "Patient/no-such-patient";
  assert.throws(() => mapResources(bad), /Patient ausente/);
  const badState = fixture();
  badState.encounters[0].status = "planned";
  assert.throws(
    () => mapResources(badState),
    /estado\/clase inpatient inválidos/,
  );
  const badDate = fixture();
  badDate.encounters[0].period.start = "2026-02-30T10:00:00Z";
  assert.throws(() => mapResources(badDate), /Fecha FHIR inválida/);
  const noZone = fixture();
  noZone.encounters[0].period.start = "2026-10-20T10:00:00";
  assert.throws(() => mapResources(noZone), /zona requerida/);
  const openEnd = fixture();
  openEnd.encounters[0].period.end = "2026-10-21T10:00:00Z";
  assert.throws(() => mapResources(openEnd), /period.end/);
});
test("SQL writes structural links and refuses patient reassociation without phantom location id", () => {
  const sql = renderSql(mapResources(fixture()));
  assert.match(sql, /fhir_patient_links/);
  assert.match(sql, /fhir_encounter_links/);
  assert.match(sql, /episode patient reassociation refused/);
  assert.doesNotMatch(sql, /location_id/);
  assert.doesNotMatch(sql, /context_notes|care_assignments/);
  assert.match(sql, /p\."fhirId"/);
  assert.match(sql, /external_reference,.*null/s);
  const custom = { organizationSlug: "org-beta", logicalKey: "source-beta" };
  const expected = uuidFor("org-beta\0source-beta", "Patient", "person-alpha");
  assert.equal(mapResources(fixture(), custom).patients[0].id, expected);
  assert.ok(
    renderSql(mapResources(fixture(), custom), custom).includes(
      uuidFor("org-beta\0source-beta", "Source", "source-beta"),
    ),
  );
});

test("SQL dollar delimiter cannot be controlled by model or source identifiers", () => {
  const model = mapResources(fixture());
  const hostile = structuredClone(model);
  hostile.patients[0].given_name = "Paciente $sync$ O'Brien";
  const options = {
    organizationSlug: "org $sync$ O'Brien",
    logicalKey: "source $sync$ O'Brien",
  };
  const sql = renderSql(hostile, options);
  const delimiter = sql.match(/^do (\$[^\n]*\$)$/m)?.[1];
  assert.ok(delimiter);
  assert.equal(sql.split(delimiter).length, 3);
  assert.ok(sql.includes("Paciente $sync$ O''Brien"));
  assert.ok(sql.includes("org $sync$ O''Brien"));
  assert.ok(sql.includes("source $sync$ O''Brien"));
});

test(
  "PostgreSQL applies sync twice and rolls all fixture changes back",
  {
    skip: process.env.FHIR_SYNC_PG_INTEGRATION !== "1",
  },
  async () => {
    const bundle = JSON.parse(
      await readFile(
        new URL(
          "../../docker/hapi-fhir/seed/demo-patients.json",
          import.meta.url,
        ),
      ),
    );
    const resources = { patients: [], encounters: [], locations: [] };
    for (const entry of bundle.entry) {
      const type = entry.resource.resourceType;
      if (type === "Patient" || type === "Encounter" || type === "Location")
        resources[`${type.toLowerCase()}s`]?.push(entry.resource);
    }
    const options = { logicalKey: "test-fhir-sync-isolated" };
    const mapping = mapResources(resources, options);
    const statement = renderSql(mapping, options);
    const changed = structuredClone(mapping);
    const changedEpisode = changed.encounters[0];
    changedEpisode.status = "discharged";
    changedEpisode.ended_at = "2026-10-22T10:00:00.000Z";
    changedEpisode.locations = [];
    const changedStatement = renderSql(changed, options);
    const sql = [
      "begin;",
      `create temporary table sync_baseline as select (select count(*) from public.care_assignments) assignments,(select count(*) from public.context_notes) notes;`,
      statement,
      statement,
      `insert into public.hospitalization_locations(organization_id,hospitalization_id,unit_id,bed_label,started_at,ended_at) select h.organization_id,h.id,l.unit_id,'test-owned-preserved', h.admitted_at - interval '1 day',h.admitted_at - interval '12 hours' from public.hospitalizations h cross join lateral (select unit_id from public.hospitalization_locations where hospitalization_id=h.id limit 1) l where h.id='${mapping.encounters[0].id}';`,
      `create temporary table preserved_location as select id from public.hospitalization_locations where hospitalization_id='${mapping.encounters[0].id}' and bed_label='test-owned-preserved';`,
      `do $assert$ declare org uuid; src uuid; begin select id into strict org from public.organizations where slug='demo-hospital'; select id into strict src from public.fhir_sources where organization_id=org and logical_key='test-fhir-sync-isolated'; if (select count(*) from public.fhir_patient_links where organization_id=org and source_id=src)<>${mapping.patients.length} then raise exception 'patient links not idempotent'; end if; if (select count(*) from public.fhir_encounter_links where organization_id=org and source_id=src)<>${mapping.encounters.length} then raise exception 'encounter links not idempotent'; end if; if (select count(*) from public.hospitalization_locations l join public.fhir_encounter_links e on e.organization_id=l.organization_id and e.hospitalization_id=l.hospitalization_id where e.organization_id=org and e.source_id=src and l.bed_label is distinct from 'test-owned-preserved')<>${mapping.encounters.reduce((n, e) => n + e.locations.length, 0)} then raise exception 'location periods not reconciled'; end if; if (select count(*) from public.hospitalization_locations l join public.fhir_encounter_links e on e.organization_id=l.organization_id and e.hospitalization_id=l.hospitalization_id where e.organization_id=org and e.source_id=src and l.ended_at is null and l.bed_label is distinct from 'test-owned-preserved')<>${mapping.encounters.reduce((n, e) => n + e.locations.filter((l) => l.ended_at === null).length, 0)} then raise exception 'current locations incorrect'; end if; if not exists(select 1 from public.hospitalization_locations l join preserved_location p on p.id=l.id where l.bed_label='test-owned-preserved') then raise exception 'unowned location was not preserved'; end if; if (select count(*) from public.care_assignments)<>(select assignments from sync_baseline) or (select count(*) from public.context_notes)<>(select notes from sync_baseline) then raise exception 'application data changed'; end if; end $assert$;`,
      changedStatement,
      `do $assert$ declare org uuid; src uuid; episode uuid := '${changedEpisode.id}'; begin select id into strict org from public.organizations where slug='demo-hospital'; select id into strict src from public.fhir_sources where organization_id=org and logical_key='test-fhir-sync-isolated'; if exists(select 1 from public.fhir_location_period_links where organization_id=org and source_id=src and hospitalization_id=episode) then raise exception 'removed source period remains owned'; end if; if not exists(select 1 from public.hospitalizations where organization_id=org and id=episode and status='discharged') then raise exception 'closed episode not reconciled'; end if; if not exists(select 1 from public.hospitalization_locations l join preserved_location p on p.id=l.id where l.bed_label='test-owned-preserved') then raise exception 'unowned location removed on source closure'; end if; if (select count(*) from public.care_assignments)<>(select assignments from sync_baseline) or (select count(*) from public.context_notes)<>(select notes from sync_baseline) then raise exception 'application data changed by reconciliation'; end if; end $assert$;`,
      "rollback;",
    ].join("\n");
    const container =
      process.env.FHIR_SYNC_DB_CONTAINER ?? "supabase_db_carer-record";
    const result = execFileSync(
      "docker",
      [
        "exec",
        "-i",
        container,
        "psql",
        "-U",
        "postgres",
        "-d",
        "postgres",
        "-v",
        "ON_ERROR_STOP=1",
        "-At",
      ],
      { input: sql, encoding: "utf8" },
    );
    assert.match(result.trim(), /ROLLBACK$/);
  },
);
test("demo seed is a stable twenty-patient, fourteen-open/six-finished inpatient transaction", async () => {
  const bundle = JSON.parse(
    await readFile(
      new URL(
        "../../docker/hapi-fhir/seed/demo-patients.json",
        import.meta.url,
      ),
    ),
  );
  assert.equal(bundle.type, "transaction");
  const patients = bundle.entry.filter(
    (x) => x.resource.resourceType === "Patient",
  );
  const encounters = bundle.entry.filter(
    (x) => x.resource.resourceType === "Encounter",
  );
  assert.equal(patients.length, 20);
  assert.equal(new Set(patients.map((x) => x.resource.id)).size, 20);
  assert.ok(patients.every((x) => /^a1000000-0000-4000-8000-[0-9]{12}$/.test(x.resource.id)));
  assert.equal(encounters.length, 20);
  assert.equal(new Set(encounters.map((x) => x.resource.subject.reference)).size, 20);
  assert.equal(
    encounters.filter((x) => x.resource.status === "in-progress").length,
    14,
  );
  assert.equal(
    encounters.filter((x) => x.resource.status === "finished").length,
    6,
  );
  for (const { resource: encounter } of encounters) {
    const start = Date.parse(encounter.period.start);
    const end = encounter.period.end ? Date.parse(encounter.period.end) : Infinity;
    assert.ok(start < end, `${encounter.id} has a valid episode period`);
    for (const { resource } of bundle.entry.filter((x) => x.resource.encounter?.reference === `Encounter/${encounter.id}`)) {
      if (resource.effectiveDateTime) assert.ok(Date.parse(resource.effectiveDateTime) >= start && Date.parse(resource.effectiveDateTime) <= end, `${resource.id} measurement outside episode`);
      // Condition onset may describe a prior history; it is not an episode measurement.
      assert.ok((resource.subject?.reference ?? resource.patient?.reference) === encounter.subject.reference, `${resource.id} patient mismatch`);
    }
  }
  assert.ok(
    bundle.entry.every(
      (x) =>
        x.request.method === "PUT" &&
        x.request.url.endsWith(`/${x.resource.id}`),
    ),
  );
});
