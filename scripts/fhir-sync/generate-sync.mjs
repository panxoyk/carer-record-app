#!/usr/bin/env node
// Genera un archivo SQL que enlaza los pacientes de HAPI FHIR con la bitácora
// de Supabase (solo desarrollo local, solo datos sintéticos).
//
// Por cada paciente de FHIR crea, de forma idempotente:
//   patients -> hospitalizations -> hospitalization_locations -> care_assignments
// Los ids de Supabase se derivan del id de FHIR (ver hospitalization_link.dart),
// así la app abre la bitácora sin consultar nada extra.
//
// Uso:
//   node scripts/fhir-sync/generate-sync.mjs [urlBaseFhir] [salida.sql] [limite] [--apply]
// Ejemplos:
//   node scripts/fhir-sync/generate-sync.mjs                 (solo genera el SQL)
//   node scripts/fhir-sync/generate-sync.mjs --apply         (genera y lo aplica en Supabase local)
//
// --apply copia el SQL al contenedor supabase_db_* y lo ejecuta con psql.
// Requiere Docker y `pnpm db:start` en marcha.

import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const args = process.argv.slice(2);
const apply = args.includes("--apply");
const positional = args.filter((arg) => !arg.startsWith("--"));

const base = (positional[0] ?? "http://127.0.0.1:8080/fhir").replace(/\/$/, "");
const outFile =
  positional[1] ??
  join(dirname(fileURLToPath(import.meta.url)), "fhir-sync.sql");
const limit = Number(positional[2] ?? 0) || Infinity;

const EXT_WARD = "urn:hospital-simulado:fhir:ward";
const EXT_BED = "urn:hospital-simulado:fhir:bed-number";
const EXT_ADMISSION = "urn:hospital-simulado:fhir:admission-date";

async function getJson(url) {
  const res = await fetch(url, {
    headers: { Accept: "application/fhir+json" },
  });
  if (!res.ok) throw new Error(`HAPI respondió ${res.status} en ${url}`);
  return res.json();
}

// Los links `next` de HAPI pueden traer otro host (localhost): se reescribe
// al de la URL base para que sean alcanzables desde este equipo.
function rebase(link) {
  const url = new URL(link);
  const target = new URL(base);
  url.protocol = target.protocol;
  url.host = target.host;
  return url.toString();
}

async function fetchPatients() {
  const patients = [];
  let url = `${base}/Patient?_count=200`;
  while (url && patients.length < limit) {
    const bundle = await getJson(url);
    for (const entry of bundle.entry ?? []) {
      if (entry.resource?.resourceType === "Patient") {
        patients.push(entry.resource);
      }
    }
    const next = (bundle.link ?? []).find((l) => l.relation === "next");
    url = next ? rebase(next.url) : null;
    process.stdout.write(`\r${patients.length} pacientes leídos…`);
  }
  process.stdout.write("\n");
  return patients.slice(0, limit);
}

const extension = (resource, url, valueKey) =>
  resource.extension?.find((e) => e.url === url)?.[valueKey];

const slug = (text) =>
  text
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");

// Literal SQL escapado; null -> null.
const lit = (value) =>
  value == null ? "null" : `'${String(value).replace(/'/g, "''")}'`;

function toRow(patient) {
  // Solo ids numéricos (los que genera HAPI): son los que se pueden mapear
  // a un UUID determinista.
  if (!/^\d{1,12}$/.test(patient.id ?? "")) return null;

  const name =
    patient.name?.find((n) => n.use === "official") ?? patient.name?.[0] ?? {};
  const given = (name.given ?? []).join(" ").trim() || "Sin nombre";
  const family = (name.family ?? "").trim() || "Sin apellido";

  const birth = /^\d{4}-\d{2}-\d{2}$/.test(patient.birthDate ?? "")
    ? patient.birthDate
    : null;

  const ward = extension(patient, EXT_WARD, "valueString")?.trim() || null;
  const bed = extension(patient, EXT_BED, "valueString")?.trim() || null;
  const admittedRaw = extension(patient, EXT_ADMISSION, "valueDateTime");
  const admittedDate = admittedRaw ? new Date(admittedRaw) : null;
  const admitted =
    admittedDate && !Number.isNaN(admittedDate.getTime())
      ? admittedDate.toISOString()
      : null;

  const padded = patient.id.padStart(12, "0");
  return {
    fhirId: patient.id,
    patientId: `f0000000-0000-0000-0000-${padded}`,
    hospitalizationId: `f1000000-0000-0000-0000-${padded}`,
    given,
    family,
    birth,
    ward,
    wardCode: ward ? `fhir-${slug(ward)}` : null,
    bed,
    admitted,
  };
}

function valuesSql(rows) {
  return rows
    .map(
      (r) =>
        `(${lit(r.fhirId)}, '${r.patientId}'::uuid, '${r.hospitalizationId}'::uuid, ` +
        `${lit(r.given)}, ${lit(r.family)}, ${lit(r.birth)}::date, ` +
        `${lit(r.ward)}, ${lit(r.wardCode)}, ${lit(r.bed)}, ${lit(r.admitted)}::timestamptz)`,
    )
    .join(",\n");
}

const patients = await fetchPatients();
const rows = patients.map(toRow).filter(Boolean);
const skipped = patients.length - rows.length;
if (rows.length === 0) {
  console.error("No hay pacientes con id numérico para sincronizar.");
  process.exit(1);
}

const inserts = [];
for (let i = 0; i < rows.length; i += 500) {
  inserts.push(
    `insert into fhir_sync values\n${valuesSql(rows.slice(i, i + 500))};`,
  );
}

const sql = `-- Generado por scripts/fhir-sync/generate-sync.mjs. Solo desarrollo local.
-- Idempotente: se puede volver a ejecutar. Hay que repetirlo tras \`pnpm db:reset\`.
begin;

create temp table fhir_sync (
  fhir_id text,
  patient_id uuid,
  hospitalization_id uuid,
  given_name text,
  family_name text,
  birth_date date,
  ward text,
  ward_code text,
  bed text,
  admitted_at timestamptz
) on commit drop;

${inserts.join("\n\n")}

do $$
declare
  org uuid;
  ana_membership uuid;
  matias_membership uuid;
  admin_membership uuid;
begin
  select id into strict org from public.organizations where slug = 'demo-hospital';

  -- Una unidad por cada sala distinta del HAPI.
  insert into public.units (organization_id, code, display_name)
  select distinct on (ward_code) org, ward_code, ward
  from fhir_sync
  where ward_code is not null
  on conflict (organization_id, code) do nothing;

  -- external_reference conserva el id de FHIR para trazabilidad.
  insert into public.patients (
    id, organization_id, external_reference, given_name, family_name,
    birth_date, care_unit, bed_label, payload
  )
  select patient_id, org, 'FHIR-' || fhir_id, given_name, family_name,
         birth_date, ward, bed, '{}'::jsonb
  from fhir_sync
  on conflict (id) do update set
    given_name = excluded.given_name,
    family_name = excluded.family_name,
    birth_date = excluded.birth_date,
    care_unit = excluded.care_unit,
    bed_label = excluded.bed_label;

  insert into public.hospitalizations (id, organization_id, patient_id, status, admitted_at)
  select hospitalization_id, org, patient_id, 'admitted', coalesce(admitted_at, now())
  from fhir_sync
  on conflict (id) do update set admitted_at = excluded.admitted_at;

  -- Ubicación vigente (solo si no tiene una abierta).
  insert into public.hospitalization_locations (
    organization_id, hospitalization_id, unit_id, bed_label, started_at
  )
  select org, s.hospitalization_id, u.id, nullif(trim(s.bed), ''), h.admitted_at
  from fhir_sync s
  join public.hospitalizations h on h.id = s.hospitalization_id
  left join public.units u on u.organization_id = org and u.code = s.ward_code
  where (s.ward_code is not null or nullif(trim(s.bed), '') is not null)
    and not exists (
      select 1 from public.hospitalization_locations l
      where l.organization_id = org
        and l.hospitalization_id = s.hospitalization_id
        and l.ended_at is null
    );

  -- Asignación asistencial vigente para los usuarios de demostración, igual
  -- que en bootstrap_synthetic_hospitalization_fixtures().
  select m.id into ana_membership
  from public.organization_memberships m
  join public.profiles p on p.id = m.profile_id
  where m.organization_id = org
    and p.auth_user_id = '11111111-1111-1111-1111-111111111111';
  select m.id into matias_membership
  from public.organization_memberships m
  join public.profiles p on p.id = m.profile_id
  where m.organization_id = org
    and p.auth_user_id = '22222222-2222-2222-2222-222222222222';
  select m.id into admin_membership
  from public.organization_memberships m
  join public.profiles p on p.id = m.profile_id
  where m.organization_id = org
    and p.auth_user_id = '33333333-3333-3333-3333-333333333333';

  insert into public.care_assignments (
    organization_id, hospitalization_id, membership_id, valid_from,
    created_by_membership_id
  )
  select org, s.hospitalization_id, x.membership_id,
         now() - interval '90 days', admin_membership
  from fhir_sync s
  cross join (values (ana_membership), (matias_membership)) as x(membership_id)
  where x.membership_id is not null and admin_membership is not null
  on conflict do nothing;
end
$$;

select count(*) as pacientes_sincronizados from fhir_sync;

commit;
`;

writeFileSync(outFile, sql, "utf8");
console.log(
  `Listo: ${rows.length} pacientes (${skipped} omitidos por id no numérico).`,
);
console.log(`Archivo: ${outFile}`);

if (apply) {
  const container = execFileSync(
    "docker",
    ["ps", "--filter", "name=supabase_db", "--format", "{{.Names}}"],
    { encoding: "utf8" },
  )
    .split(/\r?\n/)
    .map((name) => name.trim())
    .find(Boolean);
  if (!container) {
    console.error(
      "No encuentro el contenedor supabase_db_*. ¿Está corriendo `pnpm db:start`?",
    );
    process.exit(1);
  }
  console.log(`Aplicando en ${container}…`);
  execFileSync("docker", ["cp", outFile, `${container}:/tmp/fhir-sync.sql`], {
    stdio: "inherit",
  });
  execFileSync(
    "docker",
    [
      "exec",
      container,
      "psql",
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
