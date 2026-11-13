import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { bootstrapDemo } from './bootstrap-demo.mjs';

const fixture = JSON.parse(await readFile(new URL('../../docker/hapi-fhir/seed/demo-patients.json', import.meta.url), 'utf8')).entry.map(({ resource }) => resource);

function server(initial = []) {
  const store = new Map(initial.map((r) => [`${r.resourceType}/${r.id}`, structuredClone(r)]));
  const writes = [];
  const fetchImpl = async (url, options = {}) => {
    if (new URL(url).pathname.endsWith('/metadata')) return Response.json({ resourceType: 'CapabilityStatement', fhirVersion: '4.0.1', software: { name: 'HAPI FHIR Server', version: '8.12.0' }, rest: [{ mode: 'server', resource: [...new Set(fixture.map(({ resourceType }) => resourceType))].map((type) => ({ type, versioning: 'versioned-update' })) }] });
    const key = new URL(url).pathname.split('/').slice(-2).join('/');
    if (!options.method) return store.has(key) ? Response.json(store.get(key)) : new Response('', { status: 404 });
    writes.push({ key, options });
    if (options.headers['If-Match'] !== 'W/"0"') return new Response('', { status: 400 });
    if (store.has(key)) return new Response('', { status: 409 });
    store.set(key, JSON.parse(options.body));
    return new Response('', { status: 201 });
  };
  return { store, writes, fetchImpl };
}

test('bootstrap uses create-only writes and second run leaves all resources unchanged', async () => {
  const fake = server();
  assert.deepEqual(await bootstrapDemo({ baseUrl: 'http://127.0.0.1:8080/fhir', fetchImpl: fake.fetchImpl, resources: fixture }), { created: fixture.length, unchanged: 0 });
  assert.deepEqual(await bootstrapDemo({ baseUrl: 'http://127.0.0.1:8080/fhir', fetchImpl: fake.fetchImpl, resources: fixture }), { created: 0, unchanged: fixture.length });
  assert.equal(fake.writes.length, fixture.length);
  assert.ok(fake.writes.every(({ options }) => options.headers['If-Match'] === 'W/"0"'));
});

test('bootstrap rejects an unverified HAPI version before any write', async () => {
  const fake = server();
  const fetchImpl = async (url, options) => {
    if (new URL(url).pathname.endsWith('/metadata')) return Response.json({ resourceType: 'CapabilityStatement', fhirVersion: '4.0.1', software: { name: 'HAPI FHIR Server', version: '8.13.0' }, rest: [{ mode: 'server', resource: fixture.map(({ resourceType }) => ({ type: resourceType, versioning: 'versioned-update' })) }] });
    return fake.fetchImpl(url, options);
  };
  await assert.rejects(bootstrapDemo({ baseUrl: 'http://127.0.0.1:8080/fhir', fetchImpl, resources: fixture }), /pinned HAPI FHIR 8\.12\.0/);
  assert.equal(fake.writes.length, 0);
});

test('existing revisions and legitimate changes are preserved without resource rewrites', async () => {
  const existing = structuredClone(fixture[0]);
  existing.meta.versionId = '9';
  existing.meta.lastUpdated = '2026-01-01T00:00:00Z';
  existing.meta.tag.push({ system: 'https://example.test', code: 'local-review' });
  existing.name = [{ text: 'legitimately edited' }];
  let fake = server([existing]);
  assert.deepEqual(await bootstrapDemo({ baseUrl: 'http://localhost:8080/fhir', fetchImpl: fake.fetchImpl, resources: [fixture[0]] }), { created: 0, unchanged: 1 });
  const encounter = structuredClone(fixture.find((resource) => resource.resourceType === 'Encounter'));
  const updatedEncounter = structuredClone(encounter);
  updatedEncounter.status = 'finished';
  fake = server([updatedEncounter]);
  assert.deepEqual(await bootstrapDemo({ baseUrl: 'http://127.0.0.1:8080/fhir', fetchImpl: fake.fetchImpl, resources: [encounter] }), { created: 0, unchanged: 1 });
  assert.equal(fake.store.get(`Encounter/${encounter.id}`).status, 'finished');
});

test('preflight rejects a subject identity conflict before any create', async () => {
  const patient = fixture.find((resource) => resource.resourceType === 'Patient');
  const encounter = fixture.find((resource) => resource.resourceType === 'Encounter');
  const conflict = structuredClone(encounter);
  conflict.subject.reference = 'Patient/wrong';
  const fake = server([conflict]);
  await assert.rejects(bootstrapDemo({ baseUrl: 'http://127.0.0.1:8080/fhir', fetchImpl: fake.fetchImpl, resources: [patient, encounter] }), /mismatched patient\/subject/);
  assert.equal(fake.writes.length, 0);
});

test('non-synthetic existing identity and endpoint tricks fail closed', async () => {
  const untagged = structuredClone(fixture[0]);
  untagged.meta.tag = [];
  const fake = server([untagged]);
  await assert.rejects(bootstrapDemo({ baseUrl: 'http://127.0.0.1:8080/fhir', fetchImpl: fake.fetchImpl, resources: [fixture[0]] }), /not tagged synthetic/);
  assert.equal(fake.writes.length, 0);
  for (const baseUrl of ['http://u:p@localhost/fhir', 'http://localhost/fhir?x=1', 'http://localhost/fhir#x']) {
    await assert.rejects(bootstrapDemo({ baseUrl, resources: [] }), /credential-free/);
  }
});

test('bootstrap refuses non-loopback endpoints and fixture resources without HTEST', async () => {
  await assert.rejects(bootstrapDemo({ baseUrl: 'http://example.com/fhir', resources: [] }), /loopback/);
  const resource = structuredClone(fixture[0]);
  resource.meta.tag = [];
  await assert.rejects(bootstrapDemo({ baseUrl: 'http://127.0.0.1:8080/fhir', resources: [resource] }), /Refusing non-synthetic/);
});

test('bootstrap validates resource paths, the exact HTEST system, and bounded JSON responses', async () => {
  const escaped = structuredClone(fixture[0]);
  escaped.id = '../Patient/x';
  await assert.rejects(bootstrapDemo({ baseUrl: 'http://localhost/fhir', resources: [escaped] }), /Invalid FHIR resource identity/);
  const wrongSystem = structuredClone(fixture[0]);
  wrongSystem.meta.tag[0].system = 'https://example.test/HTEST';
  await assert.rejects(bootstrapDemo({ baseUrl: 'http://localhost/fhir', resources: [wrongSystem] }), /Refusing non-synthetic/);
  const fetchImpl = async () => new Response('x'.repeat(4_000_001), { status: 200 });
  await assert.rejects(bootstrapDemo({ baseUrl: 'http://localhost/fhir', fetchImpl, resources: [] }), /size limit/);
});
