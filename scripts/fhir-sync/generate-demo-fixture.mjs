import { writeFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';

const target = new URL('../../docker/hapi-fhir/seed/demo-patients.json', import.meta.url);
const base = 'http://hapi.fhir.org/baseR4';
const tag = [{ system: 'http://terminology.hl7.org/CodeSystem/v3-ActReason', code: 'HTEST' }];
const entries = [];
const add = (resource) => entries.push({ fullUrl: `${base}/${resource.resourceType}/${resource.id}`, resource: { ...resource, meta: { ...(resource.meta ?? {}), tag } }, request: { method: 'PUT', url: `${resource.resourceType}/${resource.id}` } });
const organization = 'org-demo';

add({ resourceType: 'Organization', id: organization, active: true, name: 'Hospital Sintético CRA' });
const locations = [
  ['ward-med', 'Medicina interna', 'wa'], ['ward-surg', 'Cirugía', 'wa'], ['ward-intermed', 'Cuidados intermedios', 'wa'],
  ['bed-med-12', 'Cama 12 · Medicina', 'bd', 'ward-med'], ['bed-surg-07', 'Cama 07 · Cirugía', 'bd', 'ward-surg'],
  ['bed-intermed-03', 'Cama 03 · Intermedios', 'bd', 'ward-intermed'], ['bed-shared-04', 'Cama 04 · Medicina', 'bd', 'ward-med'], ['bed-closed-04', 'Cama 04 · Observación', 'bd', 'ward-med'], ['bed-closed-05', 'Cama 05 · Recuperación', 'bd', 'ward-surg'],
];
for (const [id, name, code, parent] of locations) add({ resourceType: 'Location', id, name, status: 'active', physicalType: { coding: [{ system: 'http://terminology.hl7.org/CodeSystem/location-physical-type', code }] }, ...(parent ? { partOf: { reference: `Location/${parent}` } } : code === 'wa' ? { managingOrganization: { reference: `Organization/${organization}` } } : {}) });

const people = [
  { id: 'patient-med-01', name: ['Mercedes', 'Alvarado'], gender: 'female', birthDate: '1958-03-14', mrn: 'CRA-DEMO-MED-01' },
  { id: 'patient-surg-02', name: ['Javier', 'López'], gender: 'male', birthDate: '1971-07-02', mrn: 'CRA-DEMO-SURG-02' },
  { id: 'patient-shared-03', name: ['Lucía', 'Paredes'], gender: 'female', birthDate: '1995-02-17', mrn: 'CRA-DEMO-SHARED-03' },
  { id: 'patient-closed-04', name: ['Camila', 'Núñez'], gender: 'female', birthDate: '1991-12-08', mrn: 'CRA-DEMO-CLOSED-04' },
  { id: 'patient-closed-05', name: ['Héctor', 'Vega'], gender: 'male', birthDate: '1949-09-09', mrn: 'CRA-DEMO-CLOSED-05' },
];
for (const p of people) add({ resourceType: 'Patient', id: p.id, identifier: [{ system: 'urn:carer-record:demo:mrn', value: p.mrn }], name: [{ use: 'official', family: p.name[1], given: [p.name[0]] }], gender: p.gender, birthDate: p.birthDate });

const episodes = [
  { patient: people[0], id: 'enc-med-ana', start: '2026-10-20T08:00:00-03:00', ward: 'ward-med', bed: 'bed-med-12', diagnosis: 'Neumonía adquirida en la comunidad' },
  { patient: people[1], id: 'enc-surg-matias', start: '2026-10-20T12:00:00-03:00', ward: 'ward-surg', bed: 'bed-surg-07', diagnosis: 'Apendicitis aguda' },
  { patient: people[2], id: 'enc-shared', start: '2026-10-20T14:00:00-03:00', ward: 'ward-intermed', bed: 'bed-intermed-03', diagnosis: 'Pielonefritis aguda' },
  { patient: people[3], id: 'enc-closed-ana', start: '2026-10-18T09:00:00-03:00', end: '2026-10-19T11:00:00-03:00', ward: 'ward-med', bed: 'bed-closed-04', diagnosis: 'Deshidratación leve corregida' },
  { patient: people[4], id: 'enc-closed-matias', start: '2026-10-17T07:00:00-03:00', end: '2026-10-18T15:00:00-03:00', ward: 'ward-surg', bed: 'bed-closed-05', diagnosis: 'Hernia inguinal no complicada' },
];
const encounterRef = (e) => `Encounter/${e.id}`;
const patientRef = (e) => `Patient/${e.patient.id}`;
const dtime = (day, hour) => `2026-10-${String(day).padStart(2, '0')}T${String(hour).padStart(2, '0')}:00:00-03:00`;
const times = { 'enc-med-ana': [[20, 10], [20, 16], [21, 0], [21, 12], [22, 0], [22, 12], [23, 8]], 'enc-surg-matias': [[20, 14], [20, 20], [21, 2], [21, 10], [22, 2], [22, 10], [23, 8]], 'enc-shared': [[20, 16], [20, 22], [21, 4], [21, 12], [22, 4], [22, 12], [23, 8]] };

const obs = (e, id, time, code, label, value, unit, category = 'vital-signs', range) => ({ resourceType: 'Observation', id, status: 'final', category: [{ coding: [{ system: 'http://terminology.hl7.org/CodeSystem/observation-category', code: category }] }], code: { coding: [{ system: 'http://loinc.org', code }], text: label }, subject: { reference: patientRef(e) }, encounter: { reference: encounterRef(e) }, effectiveDateTime: time, valueQuantity: { value, unit, system: 'http://unitsofmeasure.org', code: unit }, ...(range ? { referenceRange: [{ low: { value: range[0], unit }, high: { value: range[1], unit } }] } : {}) });
const vital = (e, day, hour, index) => {
  const time = dtime(day, hour), prefix = `${e.id}-${index}`;
  const profiles = e.id === 'enc-med-ana' ? [94, 95, 95, 96, 96, 97, 97] : e.id === 'enc-surg-matias' ? [98, 98, 97, 97, 98, 98, 99] : [97, 96, 97, 98, 98, 99, 99];
  const items = [
    obs(e, `obs-${prefix}-hr`, time, '8867-4', 'Frecuencia cardiaca', 104 - Math.min(index * 3, 15), '/min', 'vital-signs', [60, 100]),
    obs(e, `obs-${prefix}-temp`, time, '8310-5', 'Temperatura corporal', 37.8 - Math.min(index * 0.15, 0.8), 'Cel', 'vital-signs', [36, 37.5]),
    obs(e, `obs-${prefix}-spo2`, time, '2708-6', 'Saturación de oxígeno en sangre arterial', profiles[index], '%', 'vital-signs', [95, 100]),
    { resourceType: 'Observation', id: `obs-${prefix}-bp`, status: 'final', category: [{ coding: [{ system: 'http://terminology.hl7.org/CodeSystem/observation-category', code: 'vital-signs' }] }], code: { coding: [{ system: 'http://loinc.org', code: '85354-9' }], text: 'Presión arterial' }, subject: { reference: patientRef(e) }, encounter: { reference: encounterRef(e) }, effectiveDateTime: time, component: [{ code: { coding: [{ system: 'http://loinc.org', code: '8480-6' }], text: 'Sistólica' }, valueQuantity: { value: 132 - index * 2, unit: 'mm[Hg]', system: 'http://unitsofmeasure.org', code: 'mm[Hg]' } }, { code: { coding: [{ system: 'http://loinc.org', code: '8462-4' }], text: 'Diastólica' }, valueQuantity: { value: 82 - index, unit: 'mm[Hg]', system: 'http://unitsofmeasure.org', code: 'mm[Hg]' } }] },
  ];
  items.forEach(add);
};

const lab = (e, day, hour, prefix, hemoglobin, crp, creatinine) => {
  const effective = dtime(day, hour);
  const results = [obs(e, `${prefix}-hb`, effective, '718-7', 'Hemoglobina', hemoglobin, 'g/dL', 'laboratory', [12, 17]), obs(e, `${prefix}-crp`, effective, '1988-5', 'Proteína C reactiva', crp, 'mg/L', 'laboratory', [0, 5]), obs(e, `${prefix}-creatinine`, effective, ' creatinine', 'Creatinina', creatinine, 'mg/dL', 'laboratory', [0.6, 1.3])];
  results[2].code.coding[0].code = '38483-4';
  results.forEach(add);
  add({ resourceType: 'DiagnosticReport', id: `report-${prefix}`, status: 'final', code: { text: 'Panel de laboratorio: hemograma y bioquímica' }, subject: { reference: patientRef(e) }, encounter: { reference: encounterRef(e) }, effectiveDateTime: effective, result: results.map(({ id }) => ({ reference: `Observation/${id}` })), conclusion: 'Datos sintéticos demostrativos; no constituyen interpretación clínica ni recomendación.' });
};

for (const e of episodes) {
  const locationPeriods = e.id === 'enc-shared'
    ? [{ location: { reference: 'Location/bed-intermed-03' }, period: { start: e.start, end: '2026-10-21T08:00:00-03:00' } }, { location: { reference: 'Location/bed-shared-04' }, period: { start: '2026-10-21T08:00:00-03:00' } }]
    : [{ location: { reference: `Location/${e.bed}` }, period: { start: e.start, ...(e.end ? { end: e.end } : {}) } }];
  add({ resourceType: 'Encounter', id: e.id, status: e.end ? 'finished' : 'in-progress', class: { system: 'http://terminology.hl7.org/CodeSystem/v3-ActCode', code: 'IMP' }, subject: { reference: patientRef(e) }, period: { start: e.start, ...(e.end ? { end: e.end } : {}) }, location: locationPeriods });
  add({ resourceType: 'Condition', id: `condition-${e.id}`, clinicalStatus: { coding: [{ system: 'http://terminology.hl7.org/CodeSystem/condition-clinical', code: e.end ? 'resolved' : 'active' }] }, code: { text: e.diagnosis }, subject: { reference: patientRef(e) }, encounter: { reference: encounterRef(e) }, onsetDateTime: e.start });
  if (e.end) {
    const isSurgery = e.patient.id === 'patient-closed-05';
    if (isSurgery) add({ resourceType: 'Procedure', id: 'procedure-closed-hernia', status: 'completed', code: { text: 'Reparación de hernia inguinal' }, subject: { reference: patientRef(e) }, encounter: { reference: encounterRef(e) }, performedDateTime: '2026-10-17T10:00:00-03:00' });
    else add({ resourceType: 'Observation', id: 'obs-closed-hydration', status: 'final', code: { text: 'Hidratación oral tolerada antes del egreso' }, subject: { reference: patientRef(e) }, encounter: { reference: encounterRef(e) }, effectiveDateTime: '2026-10-19T09:00:00-03:00', valueString: 'Tolerada' });
    continue;
  }
  for (const [index, [day, hour]] of times[e.id].entries()) vital(e, day, hour, index + 1);
  lab(e, 21, 6, `panel-${e.id}-initial`, e.id === 'enc-surg-matias' ? 13.2 : 12.1, e.id === 'enc-med-ana' ? 86 : 42, e.id === 'enc-shared' ? 1.4 : 0.9);
  lab(e, 23, 6, `panel-${e.id}-followup`, 12.4, 24, 0.9);
}

add({ resourceType: 'Condition', id: 'condition-med-diabetes', clinicalStatus: { coding: [{ system: 'http://terminology.hl7.org/CodeSystem/condition-clinical', code: 'active' }] }, code: { text: 'Diabetes mellitus tipo 2 (antecedente sintético)' }, subject: { reference: 'Patient/patient-med-01' }, encounter: { reference: 'Encounter/enc-med-ana' }, onsetDateTime: '2018-04-12' });
add({ resourceType: 'AllergyIntolerance', id: 'allergy-med-penicillin', clinicalStatus: { coding: [{ system: 'http://terminology.hl7.org/CodeSystem/allergyintolerance-clinical', code: 'active' }] }, code: { text: 'Penicilina' }, patient: { reference: 'Patient/patient-med-01' }, reaction: [{ manifestation: [{ text: 'Exantema (dato sintético)' }] }] });
add({ resourceType: 'MedicationRequest', id: 'medreq-med-amoxicillin', status: 'active', intent: 'order', medicationCodeableConcept: { text: 'Amoxicilina 500 mg, nombre y dosis de demostración' }, subject: { reference: 'Patient/patient-med-01' }, encounter: { reference: 'Encounter/enc-med-ana' }, authoredOn: '2026-10-20T10:00:00-03:00', dosageInstruction: [{ text: 'Ejemplo ficticio: 500 mg por vía oral cada 8 horas. No es indicación clínica.' }] });
add({ resourceType: 'Procedure', id: 'procedure-appendix', status: 'completed', code: { text: 'Apendicectomía laparoscópica' }, subject: { reference: 'Patient/patient-surg-02' }, encounter: { reference: 'Encounter/enc-surg-matias' }, performedDateTime: '2026-10-21T10:00:00-03:00' });
add({ resourceType: 'MedicationRequest', id: 'medreq-surg-paracetamol', status: 'active', intent: 'order', medicationCodeableConcept: { text: 'Paracetamol 500 mg (ejemplo de demostración)' }, subject: { reference: 'Patient/patient-surg-02' }, encounter: { reference: 'Encounter/enc-surg-matias' }, authoredOn: '2026-10-21T12:00:00-03:00', dosageInstruction: [{ text: 'Ejemplo ficticio: 500 mg por vía oral cada 8 horas según necesidad; no es prescripción ni consejo.' }] });

await writeFile(target, `${JSON.stringify({ resourceType: 'Bundle', type: 'transaction', entry: entries }, null, 2)}\n`);
const formatting = spawnSync('pnpm', ['exec', 'prettier', '--write', target.pathname], { stdio: 'inherit' });
if (formatting.error) throw formatting.error;
if (formatting.status !== 0) process.exit(formatting.status ?? 1);
console.log(`Wrote ${entries.length} synthetic FHIR resources for ${people.length} patients.`);
