import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { assertHapiVersionZeroCreateSupport, HAPI_VERSION_ZERO_MATCH } from './hapi-create-only.mjs';

const fixtureUrl = new URL('../../docker/hapi-fhir/seed/demo-patients.json', import.meta.url);
const HTEST_SYSTEM = 'http://terminology.hl7.org/CodeSystem/v3-ActReason';
// HAPI 8.12's CapabilityStatement is about 2 MB; keep it bounded without
// rejecting the actual pinned server's metadata response.
const MAX_BODY_BYTES = 4_000_000;
function isLoopback(url) {
  return ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname);
}
function identity(resource) {
  if (!resource || !/^[A-Z][A-Za-z0-9]{0,63}$/.test(resource.resourceType ?? '') || !/^[A-Za-z0-9.-]{1,64}$/.test(resource.id ?? '')) throw new Error('Invalid FHIR resource identity');
  return `${resource.resourceType}/${resource.id}`;
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

export async function bootstrapDemo({ baseUrl, fetchImpl = fetch, resources } = {}) {
  const base = new URL(baseUrl);
  if (base.protocol !== 'http:' || !isLoopback(base) || base.username || base.password || base.search || base.hash) throw new Error('Demo bootstrap only permits credential-free HTTP loopback HAPI URLs');
  base.pathname = `${base.pathname.replace(/\/$/, '')}/`;
  const fixture = resources ?? (await readFile(fixtureUrl, 'utf8').then(JSON.parse)).entry.map(({ resource }) => resource);
  const expected = new Map(fixture.map((resource) => [identity(resource), resource]));
  if (expected.size !== fixture.length) throw new Error('Demo fixture has duplicate resource identities');
  for (const resource of fixture) {
    if (!resource.meta?.tag?.some(({ system, code }) => system === HTEST_SYSTEM && code === 'HTEST')) throw new Error(`Refusing non-synthetic resource ${resource.resourceType}/${resource.id}`);
  }
  let ready = false;
  for (let attempt = 0; attempt < 120 && !ready; attempt++) {
    let metadata;
    try {
      metadata = await fetchImpl(new URL('metadata', base), { headers: { Accept: 'application/fhir+json' }, redirect: 'error', signal: AbortSignal.timeout(10_000) });
    } catch (error) {
      if (attempt === 119) throw error;
    }
    if (metadata?.status === 200) {
      const capability = await readJson(metadata, 'FHIR metadata');
      if (capability.resourceType !== 'CapabilityStatement' || !/^4\.0\./.test(capability.fhirVersion ?? '')) throw new Error('FHIR server must expose an R4 CapabilityStatement');
      assertHapiVersionZeroCreateSupport(capability, [...new Set([...expected.values()].map(({ resourceType }) => resourceType))]);
      ready = true;
    }
    if (!ready) await new Promise((resolve) => setTimeout(resolve, 5_000));
  }
  if (!ready) throw new Error('HAPI did not become ready within 10 minutes');
  const observed = new Map();
  // Preflight every identity before any create so an unsafe existing record cannot cause partial bootstrap.
  for (const [identity, resource] of expected) {
    const url = new URL(identity, base);
    const existingResponse = await fetchImpl(url, { headers: { Accept: 'application/fhir+json' }, redirect: 'error', signal: AbortSignal.timeout(10_000) });
    if (existingResponse.status === 200) {
      const existing = await readJson(existingResponse, `FHIR ${identity}`);
      if (!existing.meta?.tag?.some(({ system, code }) => system === HTEST_SYSTEM && code === 'HTEST')) throw new Error(`Existing ${identity} is not tagged synthetic; refusing bootstrap`);
      if (existing.resourceType !== resource.resourceType || existing.id !== resource.id) throw new Error(`Existing ${identity} has mismatched identity`);
      const expectedSubject = resource.subject?.reference ?? resource.patient?.reference;
      const actualSubject = existing.subject?.reference ?? existing.patient?.reference;
      if (expectedSubject && actualSubject !== expectedSubject) throw new Error(`Existing ${identity} has mismatched patient/subject identity`);
      if (resource.encounter?.reference && existing.encounter?.reference !== resource.encounter.reference) throw new Error(`Existing ${identity} has mismatched Encounter identity`);
      observed.set(identity, 'exists');
      continue;
    }
    if (existingResponse.status !== 404) throw new Error(`HAPI read ${identity} failed with HTTP ${existingResponse.status}`);
    observed.set(identity, 'absent');
  }
  let created = 0;
  let unchanged = 0;
  // The pinned HAPI JPA server ignores If-None-Match on PUT. Version zero can
  // never be current, so HAPI creates an absent logical ID and rejects updates.
  for (const [identity, resource] of expected) {
    const url = new URL(identity, base);
    if (observed.get(identity) === 'exists') { unchanged++; continue; }
    const response = await fetchImpl(url, { method: 'PUT', headers: { 'Content-Type': 'application/fhir+json', Accept: 'application/fhir+json', 'If-Match': HAPI_VERSION_ZERO_MATCH }, body: JSON.stringify(resource), redirect: 'error', signal: AbortSignal.timeout(10_000) });
    if (response.status === 201) { created++; continue; }
    // A concurrent writer may have won the create race. Read back and validate, never retry as an unconditional PUT.
    if (response.status === 409 || response.status === 412) {
      const reread = await fetchImpl(url, { headers: { Accept: 'application/fhir+json' }, redirect: 'error', signal: AbortSignal.timeout(10_000) });
      if (reread.status === 200) {
        const actual = await readJson(reread, `FHIR ${identity}`);
        const expectedSubject = resource.subject?.reference ?? resource.patient?.reference;
        const actualSubject = actual.subject?.reference ?? actual.patient?.reference;
        const encounterMatches = !resource.encounter?.reference || actual.encounter?.reference === resource.encounter.reference;
        if (actual.meta?.tag?.some(({ system, code }) => system === HTEST_SYSTEM && code === 'HTEST') && actual.resourceType === resource.resourceType && actual.id === resource.id && (!expectedSubject || expectedSubject === actualSubject) && encounterMatches) { unchanged++; continue; }
      }
    }
    throw new Error(`Create-only write ${identity} failed with HTTP ${response.status}`);
  }
  return { created, unchanged };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  bootstrapDemo({ baseUrl: process.env.FHIR_BASE_URL ?? 'http://127.0.0.1:8080/fhir' })
    .then((result) => console.log(`Demo HAPI bootstrap: ${result.created} created, ${result.unchanged} unchanged`))
    .catch((error) => { console.error(error.message); process.exitCode = 1; });
}
