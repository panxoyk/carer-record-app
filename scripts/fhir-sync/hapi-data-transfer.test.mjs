import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { exportSynthetic, restoreSynthetic } from './hapi-data-transfer.mjs';

const tag = [{ system: 'http://terminology.hl7.org/CodeSystem/v3-ActReason', code: 'HTEST' }];
const patient = { resourceType: 'Patient', id: 'synth-1', meta: { tag } };
const response = (body, status = 200) => new Response(JSON.stringify(body), { status });
function fetcher(url, options) {
  const path = new URL(url).pathname;
  if (path.endsWith('/metadata')) return Promise.resolve(response({ resourceType: 'CapabilityStatement', fhirVersion: '4.0.1', software: { name: 'HAPI FHIR Server', version: '8.12.0' }, rest: [{ mode: 'server', resource: [{ type: 'Patient', versioning: 'versioned-update' }] }] }));
  if (path.endsWith('/Patient/_history')) return Promise.resolve(response({ resourceType: 'Bundle', type: 'history', entry: [{ resource: { ...patient, meta: { ...patient.meta, versionId: 'v9' } } }] }));
  if (path.endsWith('/Patient')) return Promise.resolve(response({ resourceType: 'Bundle', type: 'searchset', entry: [{ resource: patient }] }));
  if (options?.method === 'PUT') return Promise.resolve(new Response(null, { status: 201 }));
  return Promise.resolve(new Response(null, { status: 404 }));
}

test('export archives synthetic current data and available history without overwriting an archive', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'hapi-transfer-')); const output = join(dir, 'backup.json');
  try {
    const result = await exportSynthetic({ baseUrl: 'http://127.0.0.1:8123/fhir', output, fetchImpl: fetcher });
    assert.deepEqual(result, { path: output, current: 1, history: 1, historyComplete: true });
    const archive = JSON.parse(await readFile(output, 'utf8'));
    assert.equal(archive.current[0].id, 'synth-1'); assert.equal(archive.history[0].meta.versionId, 'v9');
    await assert.rejects(exportSynthetic({ baseUrl: 'http://127.0.0.1:8123/fhir', output, fetchImpl: fetcher }));
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('restore is create-only, preserves logical IDs, and reports version IDs are not preserved', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'hapi-restore-')); const input = join(dir, 'backup.json');
  try {
    await import('node:fs/promises').then(({ writeFile }) => writeFile(input, JSON.stringify({ format: 'cra-hapi-synthetic-export-v1', current: [patient] })));
    const calls = [];
    const result = await restoreSynthetic({ baseUrl: 'http://127.0.0.1:8124/fhir', input, fetchImpl: async (url, options) => { calls.push(options); if (new URL(url).pathname.endsWith('/metadata')) return response({ resourceType: 'CapabilityStatement', fhirVersion: '4.0.1', software: { name: 'HAPI FHIR Server', version: '8.12.0' }, rest: [{ mode: 'server', resource: [{ type: 'Patient', versioning: 'versioned-update' }] }] }); return options.method ? new Response(null, { status: 201 }) : new Response(null, { status: 404 }); } });
    assert.deepEqual(result, { created: 1, unchanged: 0, sourceVersionIdsPreserved: false });
    assert.equal(calls[2].headers['If-Match'], 'W/"0"'); assert.equal(calls[2].method, 'PUT');
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('restore rejects conflicting existing subject or encounter before writing', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'hapi-restore-conflict-')); const input = join(dir, 'backup.json');
  const expected = { ...patient, resourceType: 'Observation', id: 'obs-1', subject: { reference: 'Patient/synth-1' }, encounter: { reference: 'Encounter/e1' } };
  try {
    await import('node:fs/promises').then(({ writeFile }) => writeFile(input, JSON.stringify({ format: 'cra-hapi-synthetic-export-v1', current: [expected] })));
    let writes = 0;
    await assert.rejects(restoreSynthetic({ baseUrl: 'http://127.0.0.1:8124/fhir', input, fetchImpl: async (url, options) => {
      if (new URL(url).pathname.endsWith('/metadata')) return response({ resourceType: 'CapabilityStatement', fhirVersion: '4.0.1', software: { name: 'HAPI FHIR Server', version: '8.12.0' }, rest: [{ mode: 'server', resource: [{ type: 'Observation', versioning: 'versioned-update' }] }] });
      if (options?.method) writes++;
      return new Response(JSON.stringify({ ...expected, subject: { reference: 'Patient/other' } }), { status: 200 });
    } }), /conflicting synthetic identity or references/);
    assert.equal(writes, 0);
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('export refuses non-loopback endpoints and non-synthetic resources', async () => {
  await assert.rejects(exportSynthetic({ baseUrl: 'http://example.com/fhir', output: '/tmp/no' }));
  await assert.rejects(exportSynthetic({ baseUrl: 'http://127.0.0.1/fhir', output: '/tmp/no', fetchImpl: async (url) => new URL(url).pathname.endsWith('/metadata') ? response({ resourceType: 'CapabilityStatement', fhirVersion: '4.0.1', rest: [{ resource: [{ type: 'Patient' }] }] }) : response({ resourceType: 'Bundle', type: 'searchset', entry: [{ resource: { resourceType: 'Patient', id: 'not-synthetic' } }] }) }));
});
