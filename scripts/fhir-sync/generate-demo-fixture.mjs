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
  { id: 'a1000000-0000-4000-8000-000000000001', label: 'med', name: ['Mercedes', 'Alvarado'], gender: 'female', birthDate: '1958-03-14', mrn: 'CRA-DEMO-MED-01' },
  { id: 'a1000000-0000-4000-8000-000000000002', label: 'surg', name: ['Javier', 'López'], gender: 'male', birthDate: '1971-07-02', mrn: 'CRA-DEMO-SURG-02' },
  { id: 'a1000000-0000-4000-8000-000000000003', label: 'shared', name: ['Lucía', 'Paredes'], gender: 'female', birthDate: '1995-02-17', mrn: 'CRA-DEMO-SHARED-03' },
  { id: 'a1000000-0000-4000-8000-000000000004', label: 'closed-04', name: ['Camila', 'Núñez'], gender: 'female', birthDate: '1991-12-08', mrn: 'CRA-DEMO-CLOSED-04' },
  { id: 'a1000000-0000-4000-8000-000000000005', label: 'closed-05', name: ['Héctor', 'Vega'], gender: 'male', birthDate: '1949-09-09', mrn: 'CRA-DEMO-CLOSED-05' },
];
for (const p of people) add({ resourceType: 'Patient', id: p.id, identifier: [{ system: 'urn:carer-record:demo:mrn', value: p.mrn }], name: [{ use: 'official', family: p.name[1], given: [p.name[0]] }], gender: p.gender, birthDate: p.birthDate });

const episodes = [
  { patient: people[0], id: 'enc-med-ana', start: '2026-10-20T08:00:00-03:00', ward: 'ward-med', bed: 'bed-med-12', diagnosis: 'Neumonía adquirida en la comunidad', secondary: 'Tos productiva y requerimiento transitorio de oxígeno', medication: 'Ceftriaxona 1 g IV cada 24 horas (orden HTEST)', procedure: 'Radiografía de tórax portátil; estudio sintético sin interpretación asistencial', allergy: 'Penicilina', reaction: 'Exantema maculopapular referido en antecedente sintético', report: 'Opacidad basal derecha ficticia; informe HTEST, sin valor diagnóstico.' },
  { patient: people[1], id: 'enc-surg-matias', start: '2026-10-20T12:00:00-03:00', ward: 'ward-surg', bed: 'bed-surg-07', diagnosis: 'Apendicitis aguda', secondary: 'Dolor abdominal localizado en evaluación posoperatoria', medication: 'Paracetamol 1 g por vía oral cada 8 horas (orden HTEST)', procedure: 'Apendicectomía laparoscópica de demostración; evolución ficticia', allergy: 'Adhesivo médico', reaction: 'Eritema local transitorio en sitio de contacto, dato HTEST', report: 'Hallazgos operatorios sintéticos compatibles con el escenario de apendicectomía.' },
  { patient: people[2], id: 'enc-shared', start: '2026-10-20T14:00:00-03:00', ward: 'ward-intermed', bed: 'bed-intermed-03', diagnosis: 'Pielonefritis aguda', secondary: 'Fiebre y dolor lumbar consignados para demostración', medication: 'Ciprofloxacino 400 mg IV cada 12 horas (orden HTEST)', procedure: 'Ecografía renal de control demostrativa; sin conclusión clínica real', allergy: 'Sulfonamidas', reaction: 'Prurito sin otros detalles, antecedente ficticio HTEST', report: 'Descripción ficticia de sistema colector sin dilatación; solo demostración.' },
  { patient: people[3], id: 'enc-closed-ana', start: '2026-10-18T09:00:00-03:00', end: '2026-10-19T11:00:00-03:00', ward: 'ward-med', bed: 'bed-closed-04', diagnosis: 'Deshidratación leve corregida', secondary: 'Disminución de ingesta oral previa al ingreso, escenario sintético', medication: 'Solución de rehidratación oral 250 mL cada 4 horas mientras despierta (orden HTEST)', procedure: 'Evaluación seriada de tolerancia oral antes del egreso', allergy: 'Kiwi', reaction: 'Molestia oral leve descrita como antecedente sintético', report: 'Controles ficticios muestran tolerancia oral documentada antes del egreso.' },
  { patient: people[4], id: 'enc-closed-matias', start: '2026-10-17T07:00:00-03:00', end: '2026-10-18T15:00:00-03:00', ward: 'ward-surg', bed: 'bed-closed-05', diagnosis: 'Hernia inguinal no complicada', secondary: 'Dolor inguinal mecánico, descripción ficticia asociada al episodio', medication: 'Ibuprofeno 400 mg por vía oral cada 8 horas con alimentos (orden HTEST)', procedure: 'Reparación de hernia inguinal abierta, procedimiento sintético completado', allergy: 'Látex', reaction: 'Urticaria de contacto descrita en antecedente HTEST', report: 'Nota operatoria ficticia: reparación completada sin incidencias para el escenario.' },
];
// Original five identities/episode IDs are stable; all added patients use
// fixed UUIDs and distinct, declarative synthetic clinical scenarios.
const addedScenarios = [
  ['Amalia', 'Riquelme', 'Neumonía viral sintética', 'Tos seca en escenario HTEST', 'Oseltamivir 75 mg cada 12 horas (orden HTEST)', 'Radiografía torácica demostrativa', 'Ácaros domésticos', 'Rinitis leve referida'],
  ['Benjamín', 'Arancibia', 'Colecistitis aguda sintética', 'Dolor en hipocondrio derecho ficticio', 'Paracetamol 500 mg cada 8 horas (orden HTEST)', 'Ecografía abdominal demostrativa', 'Mariscos', 'Prurito leve ficticio'],
  ['Catalina', 'Sepúlveda', 'Celulitis de extremidad sintética', 'Eritema local de demostración', 'Cefalexina 500 mg cada 6 horas (orden HTEST)', 'Evaluación seriada de piel HTEST', 'Yodo', 'Irritación de contacto ficticia'],
  ['Diego', 'Mardones', 'Cólico renal sintético', 'Dolor lumbar episódico ficticio', 'Ketorolaco 10 mg cada 8 horas (orden HTEST)', 'Ecografía renal demostrativa', 'Maní', 'Urticaria leve ficticia'],
  ['Elisa', 'Contreras', 'Gastroenteritis sintética', 'Náuseas y baja ingesta ficticias', 'Sales de rehidratación oral (orden HTEST)', 'Evaluación de hidratación demostrativa', 'Látex', 'Enrojecimiento de contacto ficticio'],
  ['Facundo', 'Valdés', 'Crisis asmática sintética', 'Sibilancias de escenario HTEST', 'Salbutamol inhalado (orden HTEST)', 'Espirometría demostrativa', 'Polen', 'Congestión nasal ficticia'],
  ['Gabriela', 'Orellana', 'Anemia sintética en estudio', 'Fatiga descrita para demostración', 'Sulfato ferroso 325 mg (orden HTEST)', 'Hemograma de seguimiento HTEST', 'Frutilla', 'Molestia oral ficticia'],
  ['Hernán', 'Cifuentes', 'Infección urinaria sintética', 'Disuria descrita en escenario ficticio', 'Nitrofurantoína 100 mg cada 12 horas (orden HTEST)', 'Urocultivo demostrativo', 'Clorhexidina', 'Dermatitis de contacto ficticia'],
  ['Isidora', 'Figueroa', 'Migraña sintética', 'Cefalea episódica ficticia', 'Ibuprofeno 200 mg según orden HTEST', 'Evaluación neurológica demostrativa', 'Chocolate', 'Cefalea referida como antecedente ficticio'],
  ['Joaquín', 'Salinas', 'Lumbalgia mecánica sintética', 'Dolor lumbar de demostración', 'Paracetamol 1 g cada 8 horas (orden HTEST)', 'Movilidad funcional demostrativa', 'Polvo ambiental', 'Estornudos leves ficticios'],
  ['Karina', 'Pino', 'Hipoglicemia sintética corregida', 'Temblor transitorio ficticio', 'Glucosa oral según orden HTEST', 'Control de glicemia demostrativo', 'Huevo', 'Exantema leve ficticio'],
  ['Leonardo', 'Jara', 'Esguince de tobillo sintético', 'Edema periarticular ficticio', 'Naproxeno 250 mg cada 12 horas (orden HTEST)', 'Radiografía de tobillo demostrativa', 'Aspirina', 'Reacción cutánea ficticia'],
  ['Mariana', 'Bustos', 'Otitis media sintética', 'Otalgia de escenario HTEST', 'Amoxicilina 500 mg cada 8 horas (orden HTEST)', 'Otoscopía demostrativa', 'Pescado', 'Prurito ficticio'],
  ['Nicolás', 'Leiva', 'Neumonía sintética en recuperación', 'Tos residual ficticia', 'Azitromicina 500 mg cada 24 horas (orden HTEST)', 'Control radiológico demostrativo', 'Soja', 'Molestia digestiva ficticia'],
  ['Olivia', 'Carrasco', 'Postoperatorio sintético de colecistectomía', 'Dolor incisional ficticio', 'Paracetamol 500 mg cada 8 horas (orden HTEST)', 'Curación de herida demostrativa', 'Cinta adhesiva', 'Eritema local ficticio'],
];
for (let i = 6; i <= 20; i++) {
  const n = String(i).padStart(2, '0');
  const scenario = addedScenarios[i - 6];
  const patient = { id: `a1000000-0000-4000-8000-${String(i).padStart(12, '0')}`, label: `demo-${n}`, name: [scenario[0], scenario[1]], gender: i % 2 === 0 ? 'female' : 'male', birthDate: `19${70 + (i % 25)}-0${(i % 9) + 1}-15`, mrn: `CRA-DEMO-${n}` };
  people.push(patient);
  add({ resourceType: 'Patient', id: patient.id, identifier: [{ system: 'urn:carer-record:demo:mrn', value: patient.mrn }], name: [{ use: 'official', family: patient.name[1], given: [patient.name[0]] }], gender: patient.gender, birthDate: patient.birthDate });
  const closed = i >= 17;
  const day = closed ? 10 + i - 16 : 20 + Math.floor((i - 6) / 7);
  const start = `2026-10-${String(day).padStart(2, '0')}T08:00:00-03:00`;
  const end = closed ? `2026-10-${String(day + 1).padStart(2, '0')}T12:00:00-03:00` : undefined;
  const ward = i % 3 === 0 ? 'ward-med' : i % 3 === 1 ? 'ward-surg' : 'ward-intermed';
  const bed = `bed-demo-${n}`;
  locations.push([bed, `Cama sintética ${n}`, 'bd', ward]);
  add({ resourceType: 'Location', id: bed, name: `Cama sintética ${n}`, status: 'active', physicalType: { coding: [{ system: 'http://terminology.hl7.org/CodeSystem/location-physical-type', code: 'bd' }] }, partOf: { reference: `Location/${ward}` } });
  episodes.push({ patient, id: `enc-demo-${n}`, start, ...(end ? { end } : {}), ward, bed, diagnosis: scenario[2], secondary: scenario[3], medication: scenario[4], procedure: scenario[5], allergy: scenario[6], reaction: scenario[7], report: `Informe HTEST sintético para ${scenario[2]}; sin interpretación asistencial.` });
}
const encounterRef = (e) => `Encounter/${e.id}`;
const patientRef = (e) => `Patient/${e.patient.id}`;
const dtime = (day, hour) => `2026-10-${String(day).padStart(2, '0')}T${String(hour).padStart(2, '0')}:00:00-03:00`;
const times = { 'enc-med-ana': [[20, 10], [20, 16], [21, 0], [21, 12], [22, 0], [22, 12], [23, 8]], 'enc-surg-matias': [[20, 14], [20, 20], [21, 2], [21, 10], [22, 2], [22, 10], [23, 8]], 'enc-shared': [[20, 16], [20, 22], [21, 4], [21, 12], [22, 4], [22, 12], [23, 8]], 'enc-closed-ana': [[18, 11], [18, 17], [19, 1], [19, 8]], 'enc-closed-matias': [[17, 9], [17, 15], [18, 1], [18, 12]] };
for (const e of episodes.filter(({ id }) => id.startsWith('enc-demo-'))) {
  const day = Number(e.start.slice(8, 10));
  times[e.id] = e.end ? [[day, 10], [day, 16], [day + 1, 4]] : [[day, 10], [day, 16], [day, 22], [day + 1, 4], [day + 1, 10], [day + 1, 16]];
}

const obs = (e, id, time, code, label, value, unit, category = 'vital-signs', range) => ({ resourceType: 'Observation', id, status: 'final', category: [{ coding: [{ system: 'http://terminology.hl7.org/CodeSystem/observation-category', code: category }] }], code: { coding: [{ system: 'http://loinc.org', code }], text: label }, subject: { reference: patientRef(e) }, encounter: { reference: encounterRef(e) }, effectiveDateTime: time, valueQuantity: { value, unit, system: 'http://unitsofmeasure.org', code: unit }, ...(range ? { referenceRange: [{ low: { value: range[0], unit }, high: { value: range[1], unit } }] } : {}) });
const vital = (e, day, hour, index) => {
  const time = dtime(day, hour), prefix = `${e.id}-${index}`;
  const profiles = e.id === 'enc-med-ana' ? [94, 95, 95, 96, 96, 97, 97] : e.id === 'enc-surg-matias' ? [98, 98, 97, 97, 98, 98, 99] : e.id === 'enc-shared' ? [97, 96, 97, 98, 98, 99, 99] : [96, 97, 98, 98, 98, 99, 99];
  const items = [
    obs(e, `obs-${prefix}-hr`, time, '8867-4', 'Frecuencia cardiaca', 104 - Math.min(index * 3, 15), '/min', 'vital-signs', [60, 100]),
    obs(e, `obs-${prefix}-rr`, time, '9279-1', 'Frecuencia respiratoria', 22 - Math.min(index, 6), '/min', 'vital-signs', [12, 20]),
    obs(e, `obs-${prefix}-temp`, time, '8310-5', 'Temperatura corporal', Number((37.8 - Math.min(index * 0.15, 0.8)).toFixed(2)), 'Cel', 'vital-signs', [36, 37.5]),
    obs(e, `obs-${prefix}-spo2`, time, '2708-6', 'Saturación de oxígeno en sangre arterial', profiles[index - 1], '%', 'vital-signs', [95, 100]),
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
    const isSurgery = e.patient === people[4];
    if (isSurgery) add({ resourceType: 'Procedure', id: 'procedure-closed-hernia', status: 'completed', code: { text: 'Reparación de hernia inguinal' }, subject: { reference: patientRef(e) }, encounter: { reference: encounterRef(e) }, performedDateTime: '2026-10-17T10:00:00-03:00' });
    else add({ resourceType: 'Observation', id: e.id === 'enc-closed-ana' ? 'obs-closed-hydration' : `obs-closed-hydration-${e.id}`, status: 'final', code: { text: 'Hidratación oral tolerada antes del egreso' }, subject: { reference: patientRef(e) }, encounter: { reference: encounterRef(e) }, effectiveDateTime: `${e.end.slice(0, 10)}T09:00:00-03:00`, valueString: 'Tolerada' });
  }
  for (const [index, [day, hour]] of times[e.id].entries()) vital(e, day, hour, index + 1);
  const closed = Boolean(e.end);
  const initialDay = closed ? Number(e.start.slice(8, 10)) : 21;
  const followDay = closed ? Number(e.end.slice(8, 10)) : 23;
  lab(e, initialDay, 12, `panel-${e.id}-initial`, e.id === 'enc-surg-matias' ? 13.2 : 12.1, e.id === 'enc-med-ana' ? 86 : 42, e.id === 'enc-shared' ? 1.4 : 0.9);
  lab(e, followDay, 8, `panel-${e.id}-followup`, 12.4, 24, 0.9);
  add({ resourceType: 'AllergyIntolerance', id: `allergy-${e.id}`, clinicalStatus: { coding: [{ system: 'http://terminology.hl7.org/CodeSystem/allergyintolerance-clinical', code: 'active' }] }, code: { text: e.allergy }, patient: { reference: patientRef(e) }, encounter: { reference: encounterRef(e) }, recordedDate: e.start.slice(0, 10), reaction: [{ manifestation: [{ text: e.reaction }] }] });
  add({ resourceType: 'MedicationRequest', id: `medreq-${e.id}`, status: closed ? 'completed' : 'active', intent: 'order', medicationCodeableConcept: { text: e.medication }, subject: { reference: patientRef(e) }, encounter: { reference: encounterRef(e) }, authoredOn: e.start, dosageInstruction: [{ text: `${e.medication}. Dato exclusivamente sintético, no es indicación clínica.` }] });
  add({ resourceType: 'Procedure', id: `procedure-${e.id}`, status: 'completed', code: { text: e.procedure }, subject: { reference: patientRef(e) }, encounter: { reference: encounterRef(e) }, performedDateTime: e.start });
}

add({ resourceType: 'Condition', id: 'condition-med-diabetes', clinicalStatus: { coding: [{ system: 'http://terminology.hl7.org/CodeSystem/condition-clinical', code: 'active' }] }, code: { text: 'Diabetes mellitus tipo 2 (antecedente sintético)' }, subject: { reference: patientRef(episodes[0]) }, encounter: { reference: 'Encounter/enc-med-ana' }, onsetDateTime: '2018-04-12' });
for (const e of episodes) {
  add({ resourceType: 'Condition', id: `condition-${e.id}-secondary`, clinicalStatus: { coding: [{ system: 'http://terminology.hl7.org/CodeSystem/condition-clinical', code: e.end ? 'resolved' : 'active' }] }, code: { text: e.secondary }, subject: { reference: patientRef(e) }, encounter: { reference: encounterRef(e) }, onsetDateTime: e.start });
  add({ resourceType: 'DiagnosticReport', id: `report-${e.id}-summary`, status: 'final', code: { text: `Informe de seguimiento: ${e.diagnosis}` }, subject: { reference: patientRef(e) }, encounter: { reference: encounterRef(e) }, effectiveDateTime: e.end ?? e.start, conclusion: e.report });
}

await writeFile(target, `${JSON.stringify({ resourceType: 'Bundle', type: 'transaction', entry: entries }, null, 2)}\n`);
const formatting = spawnSync('pnpm', ['exec', 'prettier', '--write', target.pathname], { stdio: 'inherit' });
if (formatting.error) throw formatting.error;
if (formatting.status !== 0) process.exit(formatting.status ?? 1);
console.log(`Wrote ${entries.length} synthetic FHIR resources for ${people.length} patients.`);
