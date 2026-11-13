import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { assertHapiVersionZeroCreateSupport, HAPI_VERSION_ZERO_MATCH } from './hapi-create-only.mjs';

const fixtureUrl = new URL('../../docker/hapi-fhir/seed/demo-patients.json', import.meta.url);
const HTEST_SYSTEM = 'http://terminology.hl7.org/CodeSystem/v3-ActReason';
const HTEST = { system: HTEST_SYSTEM, code: 'HTEST' };
const TIMEOUT_MS = 8_000;
// HAPI 8.12's CapabilityStatement is about 2 MB; keep it bounded without
// rejecting the actual pinned server's metadata response.
const MAX_BODY_BYTES = 4_000_000;

function isLoopback(url) { return ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname); }
function identity(resource) {
  if (!resource || !/^[A-Z][A-Za-z0-9]{0,63}$/.test(resource.resourceType ?? '') || !/^[A-Za-z0-9.-]{1,64}$/.test(resource.id ?? '')) throw new Error('Invalid FHIR resource identity');
  return `${resource.resourceType}/${resource.id}`;
}
function tagged(resource) { return resource?.meta?.tag?.some((tag) => tag.system === HTEST_SYSTEM && tag.code === 'HTEST') === true; }
function validZone(zone) {
  try { new Intl.DateTimeFormat('en', { timeZone: zone }).format(0); return true; } catch { return false; }
}
function institutionalDay(date, zone) {
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: zone, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(date);
  const part = (type) => parts.find((item) => item.type === type)?.value;
  return `${part('year')}-${part('month')}-${part('day')}`;
}
function stableId(encounterId, day, code) {
  return `demo-${createHash('sha256').update(`demo-hapi\0${encounterId}\0${day}\0${code}`).digest('hex').slice(0, 48)}`;
}
function timestamp(value) {
  if (!(value instanceof Date) || !Number.isFinite(value.getTime())) throw new Error('now must be a valid Date with a UTC instant');
  return value.toISOString();
}

function parseFhirInstant(value) {
  if (typeof value !== 'string' || !/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(value)) return NaN;
  const match = value.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|([+-])(\d{2}):(\d{2}))$/);
  const [, year, month, day, hour, minute, second, zone, sign, offsetHour, offsetMinute] = match;
  const calendar = new Date(Date.UTC(Number(year), Number(month) - 1, Number(day)));
  if (calendar.getUTCFullYear() !== Number(year) || calendar.getUTCMonth() + 1 !== Number(month) || calendar.getUTCDate() !== Number(day) || Number(hour) > 23 || Number(minute) > 59 || Number(second) > 59) return NaN;
  if (zone !== 'Z' && (Number(offsetHour) > 14 || Number(offsetMinute) > 59 || (Number(offsetHour) === 14 && Number(offsetMinute) !== 0))) return NaN;
  return Date.parse(value);
}

async function readJson(response, label) {
  const reader = response.body?.getReader();
  if (!reader) throw new Error(`${label} returned an empty body`);
  const chunks = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > MAX_BODY_BYTES) { await reader.cancel(); throw new Error(`${label} response exceeds size limit`); }
    chunks.push(value);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { throw new Error(`${label} returned invalid JSON`); }
}

export async function ensureDemoCurrentEvents({ baseUrl, now = new Date(), timezone = 'America/Santiago', fetchImpl = fetch, resources } = {}) {
  const capturedNow = timestamp(now);
  if (!validZone(timezone)) throw new Error('timezone must be a valid IANA timezone');
  const base = new URL(baseUrl);
  if (base.protocol !== 'http:' || !isLoopback(base) || base.username || base.password || base.search || base.hash) throw new Error('Demo FHIR only permits credential-free HTTP loopback URLs');
  base.pathname = `${base.pathname.replace(/\/$/, '')}/`;
  const fixture = resources ?? (await readFile(fixtureUrl, 'utf8').then(JSON.parse)).entry.map(({ resource }) => resource);
  const allowedPatients = new Set();
  const allowedEncounters = new Map();
  for (const resource of fixture) {
    const key = identity(resource);
    if (!tagged(resource)) throw new Error(`Fixture ${key} is not HTEST synthetic`);
    if (resource.resourceType === 'Patient') allowedPatients.add(resource.id);
    if (resource.resourceType === 'Encounter') {
      const subject = resource.subject?.reference;
      if (!/^Patient\/[A-Za-z0-9.-]{1,64}$/.test(subject ?? '')) throw new Error(`Fixture Encounter/${resource.id} has invalid synthetic Patient association`);
      allowedEncounters.set(resource.id, subject);
    }
  }
  if (!allowedPatients.size || !allowedEncounters.size || [...allowedEncounters.values()].some((subject) => !allowedPatients.has(subject.slice('Patient/'.length)))) throw new Error('Fixture must allowlist Patient and Encounter identities with exact associations');
  const request = (url, options = {}) => fetchImpl(url, { ...options, redirect: 'error', signal: AbortSignal.timeout(TIMEOUT_MS) });
  const metadataResponse = await request(new URL('metadata', base), { headers: { Accept: 'application/fhir+json' } });
  if (!metadataResponse.ok) throw new Error(`FHIR metadata failed with HTTP ${metadataResponse.status}`);
  const metadata = await readJson(metadataResponse, 'FHIR metadata');
  if (metadata.resourceType !== 'CapabilityStatement' || !/^4\.0\./.test(metadata.fhirVersion ?? '')) throw new Error('FHIR server must expose an R4 CapabilityStatement');
  assertHapiVersionZeroCreateSupport(metadata, ['Encounter', 'Patient', 'Observation']);
  const today = institutionalDay(now, timezone);
  const candidates = [];
  for (const [id, expectedSubject] of allowedEncounters) {
    const response = await request(new URL(`Encounter/${encodeURIComponent(id)}`, base), { headers: { Accept: 'application/fhir+json' } });
    if (response.status === 404) continue;
    if (!response.ok) throw new Error(`FHIR Encounter read failed with HTTP ${response.status}`);
    const encounter = await readJson(response, 'FHIR Encounter');
    if (identity(encounter) !== `Encounter/${id}` || !tagged(encounter)) throw new Error(`Encounter/${id} identity or HTEST tag mismatch`);
    if (encounter.subject?.reference !== expectedSubject) throw new Error(`Encounter/${id} subject does not match its immutable synthetic fixture association`);
    if (encounter.class?.code !== 'IMP' || encounter.status !== 'in-progress' || encounter.period?.end) continue;
    const start = parseFhirInstant(encounter.period?.start);
    if (!Number.isFinite(start)) throw new Error(`Encounter/${id} period.start must be a strict zoned FHIR instant`);
    if (start > now.getTime()) continue;
    const patientId = expectedSubject.slice('Patient/'.length);
    if (!patientId || !allowedPatients.has(patientId)) throw new Error(`Encounter/${id} subject is outside the synthetic Patient allowlist`);
    const patientResponse = await request(new URL(`Patient/${encodeURIComponent(patientId)}`, base), { headers: { Accept: 'application/fhir+json' } });
    if (!patientResponse.ok) throw new Error(`FHIR Patient read failed with HTTP ${patientResponse.status}`);
    const patient = await readJson(patientResponse, 'FHIR Patient');
    if (identity(patient) !== `Patient/${patientId}` || !tagged(patient)) throw new Error(`Patient/${patientId} identity or HTEST tag mismatch`);
    candidates.push({ encounter, patient, day: today, encounterStart: start });
  }

  let created = 0;
  let unchanged = 0;
  for (const { encounter, patient, day, encounterStart } of candidates) {
    const code = { system: 'http://loinc.org', code: '8867-4', display: 'Heart rate' };
    const id = stableId(encounter.id, day, code.code);
    const resource = {
      resourceType: 'Observation', id, status: 'final', category: [{ coding: [{ system: 'http://terminology.hl7.org/CodeSystem/observation-category', code: 'vital-signs' }] }],
      code: { coding: [code], text: code.display }, subject: { reference: `Patient/${patient.id}` }, encounter: { reference: `Encounter/${encounter.id}` },
      effectiveDateTime: capturedNow, issued: capturedNow,
      valueQuantity: { value: 58 + Number.parseInt(createHash('sha256').update(encounter.id).digest('hex').slice(0, 2), 16) % 48, unit: '/min', system: 'http://unitsofmeasure.org', code: '/min' },
      identifier: [{ system: 'https://carer-record.app/fhir/demo-observation', value: `${encounter.id}/${day}/${code.code}` }], meta: { tag: [HTEST] },
    };
    const url = new URL(`Observation/${id}`, base);
    const existingResponse = await request(url, { headers: { Accept: 'application/fhir+json' } });
    if (existingResponse.status === 200) {
      const existing = await readJson(existingResponse, 'FHIR Observation');
      validateExisting(existing, resource, day, now, timezone, encounterStart);
      unchanged++;
      continue;
    }
    if (existingResponse.status !== 404) throw new Error(`FHIR Observation read failed with HTTP ${existingResponse.status}`);
    let writeResponse;
    try {
      writeResponse = await request(url, { method: 'PUT', headers: { 'Content-Type': 'application/fhir+json', Accept: 'application/fhir+json', 'If-Match': HAPI_VERSION_ZERO_MATCH }, body: JSON.stringify(resource) });
    } catch {
      // A lost response is ambiguous: read back before deciding whether to fail.
      const recovered = await request(url, { headers: { Accept: 'application/fhir+json' } });
      if (recovered.status !== 200) throw new Error('FHIR Observation create response was lost and readback did not find it');
      validateExisting(await readJson(recovered, 'FHIR Observation'), resource, day, now, timezone, encounterStart);
      unchanged++;
      continue;
    }
    if (writeResponse.status === 201) { created++; continue; }
    if (writeResponse.status === 409 || writeResponse.status === 412) {
      const reread = await request(url, { headers: { Accept: 'application/fhir+json' } });
      if (reread.status === 200) { validateExisting(await readJson(reread, 'FHIR Observation'), resource, day, now, timezone, encounterStart); unchanged++; continue; }
    }
    throw new Error(`FHIR Observation create-only write failed with HTTP ${writeResponse.status}`);
  }
  return { created, unchanged };
}

function validateExisting(existing, expected, day, now, timezone, encounterStart) {
  const expectedIdentifier = expected.identifier[0];
  const actualQuantity = existing.valueQuantity?.value;
  if (identity(existing) !== `Observation/${expected.id}` || !tagged(existing) || existing.status !== 'final' || existing.subject?.reference !== expected.subject.reference || existing.encounter?.reference !== expected.encounter.reference || existing.identifier?.some((identifier) => identifier.system === expectedIdentifier.system && identifier.value === expectedIdentifier.value) !== true || existing.code?.coding?.some((c) => c.system === 'http://loinc.org' && c.code === '8867-4') !== true || !Number.isFinite(actualQuantity) || actualQuantity < 30 || actualQuantity > 180) throw new Error(`Existing Observation/${expected.id} has invalid synthetic daily identity or content`);
   const effective = parseFhirInstant(existing.effectiveDateTime);
  if (!Number.isFinite(effective) || effective > now.getTime() || effective < encounterStart || institutionalDay(new Date(effective), timezone) !== day) throw new Error(`Existing Observation/${expected.id} has a mismatched effective date`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  ensureDemoCurrentEvents({ baseUrl: process.env.FHIR_BASE_URL ?? 'http://127.0.0.1:8080/fhir' })
    .then((result) => console.log(`Demo current events: ${result.created} created, ${result.unchanged} unchanged`))
    .catch((error) => { console.error(error.message); process.exitCode = 1; });
}
