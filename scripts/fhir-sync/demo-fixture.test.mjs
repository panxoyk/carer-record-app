import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const bundle = JSON.parse(await readFile(new URL('../../docker/hapi-fhir/seed/demo-patients.json', import.meta.url), 'utf8'));
const entries = bundle.entry;
const byRef = new Map(entries.map(({ resource }) => [`${resource.resourceType}/${resource.id}`, resource]));
const patients = entries.filter(({ resource }) => resource.resourceType === 'Patient');
const encounters = entries.filter(({ resource }) => resource.resourceType === 'Encounter').map(({ resource }) => resource);
const scenarios = { medicine: 'enc-med-ana', surgery: 'enc-surg-matias', sharedTransfer: 'enc-shared', closedObservation: 'enc-closed-ana', closedProcedure: 'enc-closed-matias' };

test('synthetic HAPI bundle has consistent transaction identities and references', () => {
  assert.equal(bundle.type, 'transaction');
  for (const entry of entries) {
    const { resource, fullUrl, request } = entry;
    assert.equal(fullUrl, `http://hapi.fhir.org/baseR4/${resource.resourceType}/${resource.id}`);
    assert.deepEqual(request, { method: 'PUT', url: `${resource.resourceType}/${resource.id}` });
  }
  const visit = (value) => {
    if (Array.isArray(value)) return value.forEach(visit);
    if (!value || typeof value !== 'object') return;
    if (typeof value.reference === 'string' && /^[A-Z][A-Za-z]+\//.test(value.reference)) assert.ok(byRef.has(value.reference), `unresolved ${value.reference}`);
    Object.values(value).forEach(visit);
  };
  entries.forEach(visit);
  assert.equal(patients.length, 5);
  assert.deepEqual(encounters.filter((e) => e.status === 'in-progress').map((e) => e.id).sort(), ['enc-med-ana', 'enc-shared', 'enc-surg-matias']);
  assert.equal(encounters.filter((e) => e.status === 'finished').length, 2);
  assert.equal(new Set(patients.map(({ resource: p }) => p.identifier[0].value)).size, 5);
  assert.ok(entries.every(({ resource: r }) => r.meta?.tag?.some(({ code }) => code === 'HTEST')));
});

test('open episodes have temporal series and closed clinical evidence stays within episode bounds', () => {
  const clinical = entries.map(({ resource }) => resource).filter((r) => ['Observation', 'Condition', 'Procedure', 'DiagnosticReport', 'MedicationRequest'].includes(r.resourceType));
  for (const id of ['enc-med-ana', 'enc-surg-matias', 'enc-shared']) {
    const episode = encounters.find((e) => e.id === id);
    const observations = clinical.filter((r) => r.resourceType === 'Observation' && r.encounter?.reference === `Encounter/${id}`);
    assert.ok(new Set(observations.map((o) => o.effectiveDateTime)).size >= 6, `${id} needs six measurement times`);
    assert.ok(observations.length >= 12, `${id} needs at least two measures at six times`);
    for (const moment of new Set(observations.map((o) => o.effectiveDateTime))) assert.ok(observations.filter((o) => o.effectiveDateTime === moment).length >= 2, `${id} needs multiple measures at ${moment}`);
    assert.ok(observations.every((o) => o.subject.reference === episode.subject.reference));
    assert.ok(observations.every((o) => Date.parse(o.effectiveDateTime) >= Date.parse(episode.period.start)));
  }
  assert.ok(clinical.filter((r) => r.resourceType === 'Observation' && encounters.some((e) => e.status === 'in-progress' && r.encounter?.reference === `Encounter/${e.id}`)).length >= 36);
  for (const episode of encounters.filter((e) => e.status === 'finished')) {
    const start = Date.parse(episode.period.start), end = Date.parse(episode.period.end);
    for (const item of clinical.filter((r) => r.encounter?.reference === `Encounter/${episode.id}`)) {
      const time = item.effectiveDateTime ?? item.onsetDateTime ?? item.performedDateTime ?? item.authoredOn;
      assert.ok(time && Date.parse(time) >= start && Date.parse(time) <= end, `${item.id} outside ${episode.id}`);
      assert.equal(item.subject?.reference, episode.subject.reference);
    }
  }
  for (const report of clinical.filter((r) => r.resourceType === 'DiagnosticReport')) {
    assert.ok(report.result?.length);
    for (const { reference } of report.result) {
      const result = byRef.get(reference);
      assert.equal(result.resourceType, 'Observation');
      assert.equal(result.subject.reference, report.subject.reference);
      assert.equal(result.encounter.reference, report.encounter.reference);
    }
  }
  const reports = clinical.filter((r) => r.resourceType === 'DiagnosticReport');
  assert.ok(reports.length);
  for (const o of clinical.filter((r) => r.resourceType === 'Observation' && r.category?.some(({ coding }) => coding.some(({ code }) => code === 'laboratory')))) {
    assert.ok(o.code.coding.some(({ system, code }) => system === 'http://loinc.org' && /^[0-9]{1,5}-[0-9]$/.test(code)), `${o.id} has invalid LOINC code`);
  }
  const locations = encounters.flatMap((e) => e.location.map(({ location, period }) => ({ bed: location.reference, episode: e.id, start: Date.parse(period.start), end: period.end ? Date.parse(period.end) : Infinity })));
  for (let i = 0; i < locations.length; i++) for (let j = i + 1; j < locations.length; j++) {
    if (locations[i].bed === locations[j].bed && locations[i].episode !== locations[j].episode) assert.ok(locations[i].end <= locations[j].start || locations[j].end <= locations[i].start, `overlapping bed occupancy ${locations[i].bed}`);
  }
  const shared = encounters.find((e) => e.id === 'enc-shared');
  assert.ok(shared.location[0].period.end);
  assert.ok(Date.parse(shared.location[0].period.end) <= Date.parse(shared.location[1].period.start));
});

test('scenario manifest remains stable', () => {
  assert.deepEqual(Object.values(scenarios), ['enc-med-ana', 'enc-surg-matias', 'enc-shared', 'enc-closed-ana', 'enc-closed-matias']);
});
