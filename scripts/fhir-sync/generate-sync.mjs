#!/usr/bin/env node
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

export const ORGANIZATION_SLUG = "demo-hospital";
export const LOGICAL_KEY = "demo-hapi";
const ROOT = dirname(fileURLToPath(import.meta.url));
const FHIR_ID = /^[A-Za-z0-9.-]{1,64}$/;
const quote = (value) =>
  value == null ? "null" : `'${String(value).replaceAll("'", "''")}'`;
const namespaceFor = (org, source) => `${org}\0${source}`;

export function uuidFor(namespace, type, id) {
  const b = createHash("sha256")
    .update(`${namespace}\0${type}\0${id}`)
    .digest()
    .subarray(0, 16);
  b[6] = (b[6] & 15) | 80;
  b[8] = (b[8] & 63) | 128;
  const h = b.toString("hex");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

function parseInstant(value, label) {
  const form =
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;
  if (typeof value !== "string" || !form.test(value))
    throw new Error(`Fecha/hora con zona requerida: ${label}`);
  const [y, m, d] = value.slice(0, 10).split("-").map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  if (
    date.getUTCFullYear() !== y ||
    date.getUTCMonth() !== m - 1 ||
    date.getUTCDate() !== d ||
    !Number.isFinite(Date.parse(value))
  ) {
    throw new Error(`Fecha FHIR inválida: ${label}`);
  }
  return new Date(value).toISOString();
}

function refId(ref, type) {
  const m =
    typeof ref?.reference === "string" &&
    ref.reference.match(new RegExp(`^${type}/([A-Za-z0-9.-]{1,64})$`));
  if (!m)
    throw new Error(
      `Referencia ${type} inválida: ${ref?.reference ?? "(vacía)"}`,
    );
  return m[1];
}

export function mapResources(
  { patients, encounters, locations },
  { organizationSlug = ORGANIZATION_SLUG, logicalKey = LOGICAL_KEY } = {},
) {
  const ns = namespaceFor(organizationSlug, logicalKey);
  const unitCodeFor = (id) => `fhir-${createHash("sha256").update(ns).digest("hex").slice(0, 8)}-${createHash("sha256").update(id).digest("hex").slice(0, 16)}`;
  const patientMap = new Map();
  for (const p of patients) {
    if (
      p.resourceType !== "Patient" ||
      !FHIR_ID.test(p.id ?? "") ||
      patientMap.has(p.id)
    )
      throw new Error("Patient inválido o duplicado");
    const name = p.name?.find((n) => n.use === "official") ?? p.name?.[0] ?? {};
    if (!name.given?.length || !name.family?.trim())
      throw new Error(`Patient/${p.id}: nombre incompleto`);
    if (p.birthDate) {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(p.birthDate))
        throw new Error(`Patient/${p.id}: birthDate inválida`);
      parseInstant(`${p.birthDate}T00:00:00Z`, `Patient/${p.id}.birthDate`);
    }
    patientMap.set(p.id, {
      fhirId: p.id,
      id: uuidFor(ns, "Patient", p.id),
      given_name: name.given.join(" ").trim(),
      family_name: name.family.trim(),
      birth_date: p.birthDate ?? null,
    });
  }
  const sourceLocations = new Map();
  for (const l of locations) {
    if (
      l.resourceType !== "Location" ||
      !FHIR_ID.test(l.id ?? "") ||
      sourceLocations.has(l.id)
    )
      throw new Error("Location inválida o duplicada");
    sourceLocations.set(l.id, l);
  }
  const locationMap = new Map();
  for (const l of sourceLocations.values()) {
    const ward = l.physicalType?.coding?.some((c) => c.code === "wa");
    const parent = l.partOf
      ? sourceLocations.get(refId(l.partOf, "Location"))
      : null;
    if (l.partOf && !parent)
      throw new Error(`Location/${l.id}: partOf no resuelto`);
    const parentWard = parent?.physicalType?.coding?.some(
      (c) => c.code === "wa",
    );
    const wardLocation = ward ? l : parentWard ? parent : null;
    locationMap.set(l.id, {
      fhirId: l.id,
      id: uuidFor(ns, "Location", l.id),
      unit_name: wardLocation?.name?.trim() || null,
      unit_code: wardLocation ? unitCodeFor(wardLocation.id) : null,
      unit_fhir_id: wardLocation?.id ?? null,
      bed_label: ward ? null : l.name?.trim() || null,
    });
  }
  const seen = new Set();
  const mapped = encounters.map((e) => {
    if (
      e.resourceType !== "Encounter" ||
      !FHIR_ID.test(e.id ?? "") ||
      seen.has(e.id)
    )
      throw new Error("Encounter inválido o duplicado");
    seen.add(e.id);
    if (
      !["in-progress", "finished"].includes(e.status) ||
      e.class?.code !== "IMP"
    )
      throw new Error(`Encounter/${e.id}: estado/clase inpatient inválidos`);
    if (e.status === "in-progress" && e.period?.end != null)
      throw new Error(`Encounter/${e.id}: episodio abierto tiene period.end`);
    const p = patientMap.get(refId(e.subject, "Patient"));
    if (!p) throw new Error(`Encounter/${e.id}: Patient ausente`);
    const start = parseInstant(
      e.period?.start,
      `Encounter/${e.id}.period.start`,
    );
    const end =
      e.status === "finished"
        ? parseInstant(e.period?.end, `Encounter/${e.id}.period.end`)
        : null;
    if (end && Date.parse(end) < Date.parse(start))
      throw new Error(`Encounter/${e.id}: periodo invertido`);
    const ls = (e.location ?? [])
      .map((entry) => {
        const fhirId = refId(entry.location, "Location");
        const loc = locationMap.get(fhirId);
        if (!loc)
          throw new Error(`Encounter/${e.id}: Location/${fhirId} ausente`);
        const from = parseInstant(
          entry.period?.start ?? e.period.start,
          `Encounter/${e.id}.location.start`,
        );
        const to = entry.period?.end
          ? parseInstant(entry.period.end, `Encounter/${e.id}.location.end`)
          : null;
        return {
          ...loc,
          fhir_id: fhirId,
          from_at: from,
          ended_at: to,
          period_key: from,
          row_id: uuidFor(ns, "HospitalizationLocation", `${e.id}/${fhirId}/${from}`),
        };
      })
      .sort((a, b) => Date.parse(a.from_at) - Date.parse(b.from_at));
    for (let i = 0; i < ls.length; i++) {
      const l = ls[i];
      const next = ls[i + 1];
      if (!l.ended_at) l.ended_at = next?.from_at ?? end;
      if (l.ended_at && Date.parse(l.ended_at) <= Date.parse(l.from_at))
        throw new Error(`Encounter/${e.id}: intervalo ubicación inválido`);
      if (
        next &&
        l.ended_at &&
        Date.parse(l.ended_at) > Date.parse(next.from_at)
      )
        throw new Error(`Encounter/${e.id}: intervalos ubicación superpuestos`);
      if (
        Date.parse(l.from_at) < Date.parse(start) ||
        (end && l.ended_at && Date.parse(l.ended_at) > Date.parse(end))
      )
        throw new Error(`Encounter/${e.id}: ubicación fuera del episodio`);
    }
    return {
      fhirId: e.id,
      id: uuidFor(ns, "Encounter", e.id),
      patient: p,
      status: e.status === "in-progress" ? "admitted" : "discharged",
      started_at: start,
      ended_at: end,
      locations: ls,
    };
  });
  return {
    patients: [...patientMap.values()],
    locations: [...locationMap.values()],
    encounters: mapped,
  };
}

export function renderSql(
  model,
  { organizationSlug = ORGANIZATION_SLUG, logicalKey = LOGICAL_KEY } = {},
) {
  const modelJson = JSON.stringify(model);
  const interpolated = `${modelJson}${organizationSlug}${logicalKey}`;
  let tag = `$sync_${createHash("sha256").update(interpolated).digest("hex")}$`;
  for (let suffix = 0; interpolated.includes(tag); suffix += 1)
    tag = `$sync_${createHash("sha256").update(`${interpolated}\0${suffix}`).digest("hex")}$`;
  const sourceId = uuidFor(
    namespaceFor(organizationSlug, logicalKey),
    "Source",
    logicalKey,
  );
  const json = quote(modelJson);
  return [
    `do ${tag}`,
    "declare org uuid; source_uuid uuid; data jsonb := " + json + "::jsonb;",
    "begin",
    ` select id into strict org from public.organizations where slug=${quote(organizationSlug)};`,
    ` source_uuid := ${quote(sourceId)}::uuid;`,
    ` insert into public.fhir_sources(id,organization_id,logical_key) values(source_uuid,org,${quote(logicalKey)}) on conflict(organization_id,logical_key) do nothing;`,
    ` select id into strict source_uuid from public.fhir_sources where organization_id=org and logical_key=${quote(logicalKey)};`,
     ` insert into public.units(organization_id,code,display_name) select org,unit_code,unit_name from (select distinct on (unit_code) unit_code,unit_name from jsonb_to_recordset(data->'locations') as l(unit_code text,unit_name text) where unit_code is not null order by unit_code,unit_name) deduplicated on conflict(organization_id,code) do update set display_name=excluded.display_name;`,
    ` insert into public.patients(id,organization_id,external_reference,given_name,family_name,birth_date,payload) select p.id::uuid,org,null,p.given_name,p.family_name,nullif(p.birth_date,'')::date,'{}'::jsonb from jsonb_to_recordset(data->'patients') as p(id text,given_name text,family_name text,birth_date text) on conflict(id) do update set given_name=excluded.given_name,family_name=excluded.family_name,birth_date=excluded.birth_date;`,
    ` insert into public.fhir_patient_links(organization_id,source_id,fhir_id,patient_id) select org,source_uuid,p."fhirId",p.id::uuid from jsonb_to_recordset(data->'patients') as p("fhirId" text,id text) on conflict(organization_id,source_id,fhir_id) do update set patient_id=excluded.patient_id;`,
     ` insert into public.fhir_location_links(organization_id,source_id,fhir_id,unit_id) select org,source_uuid,l."fhirId",u.id from jsonb_to_recordset(data->'locations') as l("fhirId" text,unit_code text) left join public.units u on u.organization_id=org and u.code=l.unit_code on conflict(organization_id,source_id,fhir_id) do update set unit_id=excluded.unit_id;`,
    ` if exists(select 1 from jsonb_to_recordset(data->'encounters') as e(id text,patient jsonb) join public.hospitalizations h on h.organization_id=org and h.id=e.id::uuid where h.patient_id<>(e.patient->>'id')::uuid) then raise exception 'FHIR episode patient reassociation refused'; end if;`,
    ` insert into public.hospitalizations(id,organization_id,patient_id,status,admitted_at,discharged_at) select e.id::uuid,org,(e.patient->>'id')::uuid,e.status,e.started_at::timestamptz,e.ended_at::timestamptz from jsonb_to_recordset(data->'encounters') as e(id text,patient jsonb,status text,started_at text,ended_at text) on conflict(id) do update set status=excluded.status,admitted_at=excluded.admitted_at,discharged_at=excluded.discharged_at;`,
    ` insert into public.fhir_encounter_links(organization_id,source_id,fhir_id,hospitalization_id,patient_id) select org,source_uuid,e."fhirId",e.id::uuid,(e.patient->>'id')::uuid from jsonb_to_recordset(data->'encounters') as e("fhirId" text,id text,patient jsonb) on conflict(organization_id,source_id,fhir_id) do update set hospitalization_id=excluded.hospitalization_id,patient_id=excluded.patient_id;`,
     ` delete from public.hospitalization_locations l using public.fhir_location_period_links own, jsonb_to_recordset(data->'encounters') e(id text) where own.organization_id=org and own.source_id=source_uuid and own.hospitalization_id=e.id::uuid and l.organization_id=own.organization_id and l.hospitalization_id=own.hospitalization_id and l.id=own.location_row_id;`,
     ` insert into public.hospitalization_locations(id,organization_id,hospitalization_id,unit_id,bed_label,started_at,ended_at) select l.row_id::uuid,org,e.id::uuid,u.id,nullif(l.bed_label,''),l.from_at::timestamptz,nullif(l.ended_at,'')::timestamptz from jsonb_to_recordset(data->'encounters') e(id text,locations jsonb) cross join lateral jsonb_to_recordset(e.locations) l(row_id text,fhir_id text,period_key text,unit_code text,unit_name text,bed_label text,from_at text,ended_at text) left join public.fhir_location_links fl on fl.organization_id=org and fl.source_id=source_uuid and fl.fhir_id=l.fhir_id left join public.units u on u.organization_id=org and u.id=fl.unit_id;`,
     ` insert into public.fhir_location_period_links(organization_id,source_id,encounter_fhir_id,location_fhir_id,period_key,hospitalization_id,location_row_id) select org,source_uuid,e."fhirId",l.fhir_id,l.period_key,e.id::uuid,l.row_id::uuid from jsonb_to_recordset(data->'encounters') e("fhirId" text,id text,locations jsonb) cross join lateral jsonb_to_recordset(e.locations) l(fhir_id text,period_key text,row_id text);`,
    "end",
     `${tag};`,
  ].join("\n");
}

async function fetchPages(
  base,
  type,
  { timeoutMs = 10000, pageLimit = 500, resourceLimit = 100000 } = {},
) {
  const baseUrl = new URL(`${base.replace(/\/+$/, "")}/`);
  const visited = new Set();
  const resources = [];
  let url = new URL(`${type}?_count=100`, baseUrl).toString();
  for (let page = 0; url; page += 1) {
    if (page >= pageLimit)
      throw new Error(`${type}: límite de páginas excedido`);
    const requestUrl = new URL(url);
    requestUrl.protocol = baseUrl.protocol;
    requestUrl.host = baseUrl.host;
    if (visited.has(requestUrl.toString()))
      throw new Error(`${type}: ciclo de paginación`);
    visited.add(requestUrl.toString());
    const response = await fetch(requestUrl, {
      headers: { Accept: "application/fhir+json" },
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (!response.ok)
      throw new Error(`HAPI ${response.status} consultando ${type}`);
    const bundle = await response.json();
    if (bundle.resourceType === "OperationOutcome")
      throw new Error(`OperationOutcome consultando ${type}`);
    if (bundle.resourceType !== "Bundle" || bundle.type !== "searchset")
      throw new Error(`Bundle searchset inválido para ${type}`);
    resources.push(
      ...(bundle.entry ?? []).map((entry) => entry.resource).filter(Boolean),
    );
    if (resources.length > resourceLimit)
      throw new Error(`${type}: límite de recursos excedido`);
    const next = bundle.link?.find((link) => link.relation === "next")?.url;
    url = next ? new URL(next, baseUrl).toString() : null;
  }
  return resources;
}

export async function loadResources(
  base = "http://127.0.0.1:8080/fhir",
  options,
) {
  const root = `${base.replace(/\/+$/, "")}/`;
  const [patients, encounters, locations] = await Promise.all(
    ["Patient", "Encounter", "Location"].map((type) =>
      fetchPages(root, type, options),
    ),
  );
  return { patients, encounters, locations };
}

export function resolveDbContainer() {
  const wanted =
    process.env.FHIR_SYNC_DB_CONTAINER ?? "supabase_db_carer-record";
  const running = execFileSync("docker", ["ps", "--format", "{{.Names}}"], {
    encoding: "utf8",
  })
    .trim()
    .split(/\r?\n/);
  if (!running.includes(wanted))
    throw new Error(`No está activo el contenedor ${wanted}`);
  return wanted;
}

export function applySql(filename, container = resolveDbContainer()) {
  execFileSync("docker", ["cp", filename, `${container}:/tmp/fhir-sync.sql`], {
    stdio: "inherit",
  });
  execFileSync(
    "docker",
    [
      "exec",
      container,
      "psql",
      "-1",
      "-U",
      "postgres",
      "-d",
      "postgres",
      "-v",
      "ON_ERROR_STOP=1",
      "-f",
      "/tmp/fhir-sync.sql",
    ],
    { stdio: "inherit" },
  );
}

async function main(args = process.argv.slice(2)) {
  const demoAssignments = args.includes("--demo-assignments");
  const base =
    args.find((arg) => !arg.startsWith("--")) ?? "http://127.0.0.1:8080/fhir";
  const output = join(
    ROOT,
    demoAssignments ? "demo-assignments.local.sql" : "fhir-sync.local.sql",
  );
  if (demoAssignments) {
    const { default: manifest } = await import("./demo-assignments.json", {
      with: { type: "json" },
    });
    const tuples = manifest.encounters
      .map((item) => `(${quote(item.fhirId)},${quote(item.authUserId)}::uuid,${quote(item.validFrom)}::timestamptz,${quote(item.validUntil)}::timestamptz)`)
      .join(",");
    const sql = [
      "do $assign$ declare org uuid; source_uuid uuid; creator uuid; item record; member_id uuid; episode_id uuid; begin",
      "select id into strict org from public.organizations where slug='demo-hospital';",
      "select id into strict source_uuid from public.fhir_sources where organization_id=org and logical_key='demo-hapi';",
      "select id into strict creator from public.organization_memberships where organization_id=org and profile_id=(select id from public.profiles where auth_user_id='33333333-3333-3333-3333-333333333333');",
       `for item in select * from (values ${tuples}) as entries(fhir_id,auth_user_id,valid_from,valid_until) loop`,
      "select hospitalization_id into strict episode_id from public.fhir_encounter_links where organization_id=org and source_id=source_uuid and fhir_id=item.fhir_id;",
      "select m.id into strict member_id from public.organization_memberships m join public.profiles p on p.id=m.profile_id where m.organization_id=org and p.auth_user_id=item.auth_user_id::uuid;",
       "if not exists(select 1 from public.care_assignments a where a.organization_id=org and a.hospitalization_id=episode_id and a.membership_id=member_id) then insert into public.care_assignments(organization_id,hospitalization_id,membership_id,valid_from,valid_until,created_by_membership_id) values(org,episode_id,member_id,item.valid_from,item.valid_until,creator); end if;",
      "end loop; end $assign$;",
    ].join("\n");
    writeFileSync(output, sql);
    applySql(output);
    return;
  }
  const options = {
    organizationSlug: process.env.FHIR_SYNC_ORGANIZATION ?? ORGANIZATION_SLUG,
    logicalKey: process.env.FHIR_SYNC_LOGICAL_KEY ?? LOGICAL_KEY,
  };
  const mapped = mapResources(await loadResources(base), options);
  writeFileSync(output, renderSql(mapped, options));
  console.log(
    `Mapped ${mapped.patients.length} Patient, ${mapped.encounters.length} Encounter, ${mapped.locations.length} Location; source=${options.logicalKey}; ${output}`,
  );
  if (args.includes("--apply")) applySql(output);
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
