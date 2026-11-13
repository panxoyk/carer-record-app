import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { ensureDemoCurrentEvents } from './ensure-demo-current-events.mjs';

const fixture = JSON.parse(await readFile(new URL('../../docker/hapi-fhir/seed/demo-patients.json', import.meta.url), 'utf8')).entry.map(({ resource }) => resource);
const now = new Date('2026-10-23T15:00:00.000Z');

function server({ mutateEncounter, mutatePatient, conflict = false, loseResponse = false } = {}) {
  const store = new Map(fixture.map((resource) => [`${resource.resourceType}/${resource.id}`, structuredClone(resource)]));
  if (mutateEncounter) mutateEncounter(store.get('Encounter/enc-med-ana'));
  if (mutatePatient) mutatePatient(store.get('Patient/a1000000-0000-4000-8000-000000000001'));
  const writes = [];
  const fetchImpl = async (input, options = {}) => {
    const url = new URL(input);
    if (url.pathname.endsWith('/metadata')) return Response.json({ resourceType: 'CapabilityStatement', fhirVersion: '4.0.1', software: { name: 'HAPI FHIR Server', version: '8.12.0' }, rest: [{ mode: 'server', resource: [...new Set(fixture.map(({ resourceType }) => resourceType))].map((type) => ({ type, versioning: 'versioned-update' })) }] });
    const key = url.pathname.split('/').slice(-2).join('/');
    if (!options.method) return store.has(key) ? Response.json(store.get(key)) : new Response('', { status: 404 });
    writes.push({ key, options });
    if (options.headers['If-Match'] !== 'W/"0"') return new Response('', { status: 400 });
    if (conflict) { store.set(key, JSON.parse(options.body)); return new Response('', { status: 409 }); }
    if (store.has(key)) return new Response('', { status: 409 });
    store.set(key, JSON.parse(options.body));
    if (loseResponse) throw new Error('simulated response loss');
    return new Response('', { status: 201 });
  };
  return { store, writes, fetchImpl };
}

test('creates one stable HTEST observation for each current open episode and reuses it', async () => {
  const fake = server();
  const options = { baseUrl: 'http://127.0.0.1:8080/fhir', fetchImpl: fake.fetchImpl, now };
  assert.deepEqual(await ensureDemoCurrentEvents(options), { created: 14, unchanged: 0 });
  const observations = [...fake.store.values()].filter((resource) => resource.resourceType === 'Observation' && resource.meta?.tag?.some((tag) => tag.code === 'HTEST'));
  const created = observations.filter((resource) => resource.identifier?.some((identifier) => identifier.system === 'https://carer-record.app/fhir/demo-observation'));
  assert.equal(created.length, 14);
  assert.ok(created.every((resource) => resource.effectiveDateTime === now.toISOString() && resource.encounter.reference.startsWith('Encounter/')));
  const persisted = created.map((resource) => JSON.stringify(resource));
  assert.deepEqual(await ensureDemoCurrentEvents(options), { created: 0, unchanged: 14 });
  assert.deepEqual(created.map((resource) => JSON.stringify(fake.store.get(`Observation/${resource.id}`))), persisted);
  assert.deepEqual(await ensureDemoCurrentEvents({ ...options, now: new Date('2026-10-24T15:00:00Z') }), { created: 14, unchanged: 0 });
  assert.equal(fake.writes.length, 28);
});

test('skips closed, future, non-IMP and ended encounters without writing', async () => {
  const fake = server({ mutateEncounter(encounter) { encounter.period.start = '2026-10-24T10:00:00Z'; } });
  await ensureDemoCurrentEvents({ baseUrl: 'http://localhost:8080/fhir', fetchImpl: fake.fetchImpl, now });
  assert.equal(fake.writes.length, 13);
  const ended = server({ mutateEncounter(encounter) { encounter.period.end = '2026-10-22T00:00:00Z'; } });
  await ensureDemoCurrentEvents({ baseUrl: 'http://localhost:8080/fhir', fetchImpl: ended.fetchImpl, now });
  assert.equal(ended.writes.length, 13);
});

test('rejects unsafe, mismatched, non-synthetic identities and invalid clocks/timezones', async () => {
  const escaped = structuredClone(fixture);
  escaped.find((resource) => resource.resourceType === 'Encounter').id = '../Patient/x';
  await assert.rejects(ensureDemoCurrentEvents({ baseUrl: 'http://localhost/fhir', resources: escaped, now }), /Invalid FHIR resource identity/);
  const mismatched = server({ mutateEncounter(encounter) { encounter.subject.reference = 'Patient/external'; } });
  await assert.rejects(ensureDemoCurrentEvents({ baseUrl: 'http://localhost/fhir', fetchImpl: mismatched.fetchImpl, now }), /subject does not match its immutable synthetic fixture association/);
  const untagged = server({ mutatePatient(patient) { patient.meta.tag = []; } });
  await assert.rejects(ensureDemoCurrentEvents({ baseUrl: 'http://localhost/fhir', fetchImpl: untagged.fetchImpl, now }), /identity or HTEST tag mismatch/);
  for (const baseUrl of ['http://example.com/fhir', 'http://user:pass@localhost/fhir', 'https://localhost/fhir']) await assert.rejects(ensureDemoCurrentEvents({ baseUrl, now }), /credential-free HTTP loopback/);
  await assert.rejects(ensureDemoCurrentEvents({ baseUrl: 'http://localhost/fhir', now: new Date('invalid') }), /valid Date/);
  await assert.rejects(ensureDemoCurrentEvents({ baseUrl: 'http://localhost/fhir', now, timezone: 'Mars/Olympus' }), /valid IANA/);
});

test('requires each Encounter to retain its exact fixture Patient and a strict zoned instant', async () => {
  const wrongFixture = structuredClone(fixture);
  const encounter = wrongFixture.find((resource) => resource.resourceType === 'Encounter');
  encounter.subject.reference = 'Patient/a1000000-0000-4000-8000-000000000002';
  const fake = server();
  await assert.rejects(ensureDemoCurrentEvents({ baseUrl: 'http://localhost/fhir', resources: wrongFixture, fetchImpl: fake.fetchImpl, now }), /subject does not match its immutable synthetic fixture association/);
  assert.equal(fake.writes.length, 0);
  for (const start of ['2026-02-30T12:00:00Z', '2026-10-23', '2026-10-23T12:00:00', '2026-10-23T12:00:00+15:00']) {
    const invalid = server({ mutateEncounter(item) { item.period.start = start; } });
    await assert.rejects(ensureDemoCurrentEvents({ baseUrl: 'http://localhost/fhir', fetchImpl: invalid.fetchImpl, now }), /strict zoned FHIR instant/);
    assert.equal(invalid.writes.length, 0);
  }
});

test('races and a lost create response converge by validating the persisted winner', async () => {
  for (const behavior of [{ conflict: true }, { loseResponse: true }]) {
    const fake = server(behavior);
    assert.deepEqual(await ensureDemoCurrentEvents({ baseUrl: 'http://localhost/fhir', fetchImpl: fake.fetchImpl, now }), { created: 0, unchanged: 14 });
  }
});

test('rejects a daily observation dated before its Encounter period start', async () => {
  const fake = server();
  const options = { baseUrl: 'http://localhost:8080/fhir', fetchImpl: fake.fetchImpl, now };
  await ensureDemoCurrentEvents(options);
  const encounter = fake.store.get('Encounter/enc-med-ana');
  encounter.period.start = '2026-10-23T12:00:00.000Z';
  const observation = [...fake.store.values()].find((resource) => resource.resourceType === 'Observation' && resource.encounter?.reference === 'Encounter/enc-med-ana' && resource.identifier?.some((item) => item.system === 'https://carer-record.app/fhir/demo-observation'));
  observation.effectiveDateTime = '2026-10-23T11:00:00.000Z';
  await assert.rejects(ensureDemoCurrentEvents(options), /mismatched effective date/);
});

test('local day identity handles year boundaries and DST using the institutional timezone', async () => {
  const fake = server();
  await ensureDemoCurrentEvents({ baseUrl: 'http://localhost/fhir', fetchImpl: fake.fetchImpl, now: new Date('2026-11-01T03:30:00Z') });
  const idsBefore = [...fake.store.keys()].filter((key) => key.startsWith('Observation/demo-')).sort();
  await ensureDemoCurrentEvents({ baseUrl: 'http://localhost/fhir', fetchImpl: fake.fetchImpl, now: new Date('2026-11-01T04:30:00Z') });
  const idsAfter = [...fake.store.keys()].filter((key) => key.startsWith('Observation/demo-')).sort();
  assert.deepEqual(idsAfter, idsBefore);
  await ensureDemoCurrentEvents({ baseUrl: 'http://localhost/fhir', fetchImpl: fake.fetchImpl, now: new Date('2027-01-01T03:30:00Z') });
  assert.equal([...fake.store.keys()].filter((key) => key.startsWith('Observation/demo-')).length, 28);
});
