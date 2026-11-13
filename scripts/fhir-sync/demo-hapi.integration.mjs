import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { createServer } from 'node:net';
import { randomUUID } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { bootstrapDemo } from './bootstrap-demo.mjs';
import { ensureDemoCurrentEvents } from './ensure-demo-current-events.mjs';
import { restoreSynthetic } from './hapi-data-transfer.mjs';

const HAPI_IMAGE = 'hapiproject/hapi@sha256:0ff86aac4c7bd13a1ee226444a70263bb46ed1c28ef543c30a44f865b80ca04e';
const INIT_IMAGE = 'alpine@sha256:49340b346798875b5592e5d420241f2f9cfba5f47e62ebb1446a1b34734e898f';
const HTEST = { system: 'http://terminology.hl7.org/CodeSystem/v3-ActReason', code: 'HTEST' };
const fixtureUrl = new URL('../../docker/hapi-fhir/seed/demo-patients.json', import.meta.url);

function docker(...args) {
  return execFileSync('docker', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
}
async function freePort() {
  const server = createServer();
  await new Promise((resolve, reject) => server.once('error', reject).listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  await new Promise((resolve) => server.close(resolve));
  return port;
}
const dayInZone = (date, zone) => new Intl.DateTimeFormat('en-CA', { timeZone: zone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(date);
const shiftDay = (dateString, amount) => {
  const date = new Date(`${dateString}T12:00:00Z`);
  date.setUTCDate(date.getUTCDate() + amount);
  return date.toISOString().slice(0, 10);
};
async function readResource(base, path) {
  const response = await fetch(new URL(path, `${base}/`), { headers: { Accept: 'application/fhir+json' }, redirect: 'error', signal: AbortSignal.timeout(15_000) });
  if (!response.ok) throw new Error(`FHIR read ${path} failed: ${response.status}`);
  return response.json();
}
async function waitReady(base) {
  for (let attempt = 0; attempt < 120; attempt++) {
    try {
      const response = await fetch(`${base}/metadata`, { headers: { Accept: 'application/fhir+json' }, redirect: 'error', signal: AbortSignal.timeout(5_000) });
      if (response.ok) return;
    } catch { /* wait for this disposable container only */ }
    await new Promise((resolve) => setTimeout(resolve, 5_000));
  }
  throw new Error('Disposable HAPI did not become ready within 10 minutes');
}
async function clinicalCounts(base, today, previousDay) {
  const deno = execFileSync('deno', [
    'run', '--config', 'supabase/functions/deno.json', '--lock', 'supabase/functions/deno.lock', '--frozen',
    `--allow-net=127.0.0.1:${new URL(base).port}`, '--allow-env=FHIR_DEMO_HAPI_INTEGRATION',
    'scripts/fhir-sync/demo-hapi-clinical-record.integration.ts', base, today, previousDay,
  ], { encoding: 'utf8', env: { ...process.env, FHIR_DEMO_HAPI_INTEGRATION: '1' }, stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  return JSON.parse(deno.split('\n').at(-1));
}

export async function runDisposableHapiIntegration() {
  if (process.env.FHIR_DEMO_HAPI_INTEGRATION !== '1') throw new Error('Refusing Docker integration without FHIR_DEMO_HAPI_INTEGRATION=1');
  if (!docker('image', 'inspect', HAPI_IMAGE)) throw new Error('Pinned HAPI image is not locally available; this integration does not pull images');
  if (!docker('image', 'inspect', INIT_IMAGE)) throw new Error('Pinned volume-init image is not locally available; this integration does not pull images');

  const suffix = `${process.pid}-${randomUUID().slice(0, 8)}`;
  const volume = `cra-hapi-it-${suffix}`;
  const container = `cra-hapi-it-${suffix}`;
  const port = await freePort();
  const baseUrl = `http://127.0.0.1:${port}/fhir`;
  let volumeCreated = false;
  let containerCreated = false;
  const fixture = JSON.parse(await readFile(fixtureUrl, 'utf8')).entry.map(({ resource }) => resource);
  const patient = fixture.find((resource) => resource.resourceType === 'Patient' && resource.id === 'a1000000-0000-4000-8000-000000000001');
  const observationFixture = fixture.find((resource) => resource.resourceType === 'Observation' && resource.encounter?.reference === 'Encounter/enc-med-ana');
  if (!patient || !observationFixture || !fixture.length) throw new Error('Expected synthetic fixture resources are missing');

  const startContainer = () => {
    const id = docker('run', '-d', '--name', container, '--label', 'purpose=cra-hapi-integration-test',
      '-p', `127.0.0.1:${port}:8080`, '-e', 'JAVA_TOOL_OPTIONS=-Xms256m -Xmx1g',
      '-e', 'SPRING_DATASOURCE_URL=jdbc:h2:file:/data/hapi/hapi;DB_CLOSE_ON_EXIT=FALSE',
      '-v', `${volume}:/data/hapi`, HAPI_IMAGE);
    containerCreated = true;
    return id;
  };

  try {
    docker('volume', 'create', volume);
    volumeCreated = true;
    // Mirrors the compose init service; only this invocation's dedicated volume is mounted.
    docker('run', '--rm', '--user', '0:0', '--label', 'purpose=cra-hapi-integration-test',
      '-v', `${volume}:/volume`, INIT_IMAGE, 'sh', '-c', 'chown -R 65532:65532 /volume');
    startContainer();
    await waitReady(`http://127.0.0.1:${port}/fhir`);

    const boot = await bootstrapDemo({ baseUrl });
    assert.deepEqual(boot, { created: fixture.length, unchanged: 0 });
    assert.deepEqual(await bootstrapDemo({ baseUrl }), { created: 0, unchanged: fixture.length });

    const createOnly = async (id, name) => fetch(`${baseUrl}/Organization/${id}`, {
      method: 'PUT', headers: { 'Content-Type': 'application/fhir+json', 'If-Match': 'W/"0"' },
      body: JSON.stringify({ resourceType: 'Organization', id, active: true, name, meta: { tag: [HTEST] } }),
    });
    const sequentialId = `ifmatch-sequential-${suffix}`;
    const sequentialFirst = await createOnly(sequentialId, 'original synthetic value');
    const sequentialSecond = await createOnly(sequentialId, 'different synthetic value');
    const sequentialStored = await readResource(baseUrl, `Organization/${sequentialId}`);
    assert.equal(sequentialFirst.status, 201);
    assert.equal(sequentialSecond.status, 409);
    assert.equal(sequentialStored.name, 'original synthetic value');

    const concurrentId = `ifmatch-concurrent-${suffix}`;
    const race = await Promise.all([createOnly(concurrentId, 'writer one'), createOnly(concurrentId, 'writer two')]);
    const concurrentStored = await readResource(baseUrl, `Organization/${concurrentId}`);
    assert.deepEqual(race.map((response) => response.status).sort(), [201, 409]);
    assert.equal(concurrentStored.meta.versionId, '1');

    const temp = await mkdtemp(join(tmpdir(), 'cra-hapi-transfer-'));
    let transferResults;
    try {
      const archive = join(temp, 'restore.json');
      const restoreObservation = {
        resourceType: 'Observation', id: `restore-${suffix}`, status: 'final', meta: { tag: [HTEST] },
        code: { text: 'Synthetic restore probe' }, subject: { reference: `Patient/${patient.id}` },
        encounter: { reference: 'Encounter/enc-med-ana' }, effectiveDateTime: new Date().toISOString(),
      };
      await writeFile(archive, JSON.stringify({ format: 'cra-hapi-synthetic-export-v1', current: [patient, restoreObservation] }));
      const firstRestore = await restoreSynthetic({ baseUrl, input: archive });
      const secondRestore = await restoreSynthetic({ baseUrl, input: archive });
      assert.deepEqual(firstRestore, { created: 1, unchanged: 1, sourceVersionIdsPreserved: false });
      assert.deepEqual(secondRestore, { created: 0, unchanged: 2, sourceVersionIdsPreserved: false });
      const conflict = structuredClone(restoreObservation);
      conflict.subject.reference = 'Patient/a1000000-0000-4000-8000-000000000002';
      await writeFile(archive, JSON.stringify({ format: 'cra-hapi-synthetic-export-v1', current: [conflict] }));
      await assert.rejects(restoreSynthetic({ baseUrl, input: archive }), /conflicting synthetic identity or references/);
      transferResults = { firstRestore, secondRestore, conflictRejected: true };
    } finally { await rm(temp, { recursive: true, force: true }); }

    const today = dayInZone(new Date(), 'America/Santiago');
    const previousDay = shiftDay(today, -1);
    const olderDay = shiftDay(today, -2);
    const fixedFirst = await ensureDemoCurrentEvents({ baseUrl, now: new Date(`${olderDay}T16:00:00Z`) });
    const fixedRepeat = await ensureDemoCurrentEvents({ baseUrl, now: new Date(`${olderDay}T16:00:00Z`) });
    const fixedNext = await ensureDemoCurrentEvents({ baseUrl, now: new Date(`${previousDay}T16:00:00Z`) });
    assert.deepEqual(fixedFirst, { created: 14, unchanged: 0 });
    assert.deepEqual(fixedRepeat, { created: 0, unchanged: 14 });
    assert.deepEqual(fixedNext, { created: 14, unchanged: 0 });

    const oldRangeBeforeToday = await clinicalCounts(baseUrl, today, previousDay);
    const currentFirst = await ensureDemoCurrentEvents({ baseUrl });
    const currentRepeat = await ensureDemoCurrentEvents({ baseUrl });
    assert.deepEqual(currentFirst, { created: 14, unchanged: 0 });
    assert.deepEqual(currentRepeat, { created: 0, unchanged: 14 });
    const oldRangeAfterToday = await clinicalCounts(baseUrl, today, previousDay);
    assert.equal(oldRangeAfterToday.previousDayObservations, oldRangeBeforeToday.previousDayObservations);
    assert.ok(oldRangeAfterToday.todayObservations > 0);

    const patientBefore = await readResource(baseUrl, `Patient/${patient.id}`);
    const encounterBefore = await readResource(baseUrl, 'Encounter/enc-med-ana');
    docker('stop', container);
    docker('rm', container);
    containerCreated = false;
    startContainer();
    await waitReady(`http://127.0.0.1:${port}/fhir`);
    const patientAfter = await readResource(baseUrl, `Patient/${patient.id}`);
    const encounterAfter = await readResource(baseUrl, 'Encounter/enc-med-ana');
    assert.equal(patientAfter.id, patientBefore.id);
    assert.equal(patientAfter.meta.versionId, patientBefore.meta.versionId);
    assert.equal(encounterAfter.id, encounterBefore.id);
    assert.equal(encounterAfter.meta.versionId, encounterBefore.meta.versionId);
    assert.equal((await bootstrapDemo({ baseUrl })).unchanged, fixture.length);
    const dailySearch = await readResource(baseUrl, `Observation?encounter=Encounter/enc-med-ana&date=ge${today}&date=lt${shiftDay(today, 1)}`);
    assert.ok((dailySearch.total ?? dailySearch.entry?.length ?? 0) >= 1);

    return {
      image: HAPI_IMAGE,
      resources: fixture.length,
      bootstrap: { first: boot.created, replayUnchanged: fixture.length },
      conditionalCreate: { sequential: [sequentialFirst.status, sequentialSecond.status], concurrent: race.map((r) => r.status), oneVersionWinner: concurrentStored.meta.versionId },
      transfer: transferResults,
      daily: { fixedDay: fixedFirst.created, sameDayRepeat: fixedRepeat.unchanged, nextDay: fixedNext.created, currentDay: currentFirst.created, currentRepeat: currentRepeat.unchanged },
      clinicalRecord: oldRangeAfterToday,
      persistence: { patientVersion: patientAfter.meta.versionId, encounterVersion: encounterAfter.meta.versionId, dailyObservationSearch: dailySearch.total ?? dailySearch.entry?.length ?? 0 },
    };
  } finally {
    if (containerCreated) {
      try { docker('rm', '-f', container); } catch { /* exact unique container name only */ }
    }
    if (volumeCreated) {
      try { docker('volume', 'rm', volume); } catch { /* exact unique volume created above only */ }
    }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  runDisposableHapiIntegration()
    .then((result) => console.log(JSON.stringify(result)))
    .catch((error) => { console.error(error.message); process.exitCode = 1; });
}
