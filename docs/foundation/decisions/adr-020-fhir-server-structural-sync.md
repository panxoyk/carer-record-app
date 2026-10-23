# ADR-020: Sincronización estructural FHIR y consulta clínica autorizada

- Estado: Aceptada
- Fecha: 2026-10-23
- Alcance: contrato y corte mínimo implementado de sincronización estructural, consulta autorizada y cliente Flutter tipado; no es ingesta clínica completa.
- Relación: sucede y sustituye ADR-019 para la dirección de consulta; mantiene el límite de datos sintéticos/locales.

## Decisión

La sincronización estructural vincula `Patient` con `patients`, `Encounter` con `hospitalizations` y `Location` con `units` (o una ubicación externa sin unidad interna). Las identidades se componen de tenant, fuente, tipo implícito en tabla y `Resource.id` texto; no se exige ID numérico. `fhir_sources.logical_key` es identificador lógico servidor, nunca URL ni secreto. Las relaciones mantienen FKs compuestas por tenant y referencias directas a episodio/paciente; no se admite una entidad polimórfica sin constraints.

Primera unidad DB: `fhir_sources`, `fhir_patient_links`, `fhir_encounter_links`, `fhir_location_links` y `fhir_location_period_links`; escritor usa sincronización idempotente y conserva coherencia paciente/episodio/periodo de ubicación. Los IDs FHIR son texto validado con `[A-Za-z0-9.-]{1,64}`; `logical_key` acepta `[A-Za-z0-9._-]{1,64}` y no es URL configurable. `fhir_location_links.unit_id` es nullable: no se inventa un ID local para una `Location` sin unidad interna. No conceder acceso móvil directo a estas tablas.

La pasarela implementada es Edge Function `clinical-record`, invocada con JWT de sesión; nunca hay acceso móvil directo a HAPI. Valida JWT antes de operaciones privilegiadas y consulta `fhir_authorized_encounter_context(organizationId, hospitalizationId, purpose)`. La RPC devuelve solo `source_id`, IDs FHIR de Patient/Encounter y organization/hospitalization/patient IDs. No entrega URLs, secretos ni payloads. `record` requiere `clinical.census.read` y `clinical.patient.read`, y autorización exacta de episodio mediante `clinical.assigned.read`, membresía y helper; `timeline` exige además `clinical.timeline.read`. La excepción de Administrador de demo se mantiene únicamente por helper/RLS actual, sin confiar en nombres de rol.

Contrato implementado `POST /clinical-record`. `purpose` es opcional y por defecto `record`; los propósitos válidos son `record` y `timeline`:

```json
{ "organizationId": "uuid", "hospitalizationId": "uuid", "purpose": "record" }
```

Respuesta tipada: `{status: "complete"|"partial", truncated: boolean, freshness: {retrievedAt: string, sourceUpdatedAt: string|null}, patient: {id: string, name: string, identifier: string|null, birthDate: string|null, gender: string|null}, hospitalization: {id: string, status: string, admittedAt: string, dischargedAt: string|null, unit: string|null, bed: string|null}, sections: [{type: string, entries: [{id: string, title: string, detail: string|null, date: string|null, isDateOnly: boolean, sourceKind: string}]}], timeline: [{id: string, occurredAt: string|null, precision: string|null, resourceType: string, title: string, detail: string|null}]}`. `patient.id` es el ID interno; cada `sourceKind`/ID de entrada identifica la fuente como `demo-hapi/<type>/<id>`. Los IDs de entradas/timeline son estables por fuente y recurso. No se retorna JSON FHIR crudo. La pasarela obtiene URL y credenciales exclusivamente de configuración servidor.

La consulta de censo/lista usa la vista `fhir_clinical_census_by_hospitalization` y RLS. `record` requiere `clinical.census.read` y `clinical.patient.read` más autorización exacta del episodio por la ruta `clinical.assigned.read`/membresía/helper; `timeline` exige además `clinical.timeline.read`. La excepción existente de Administrador demo conserva `clinical.organization.read`, alcance y guardas RLS; no depende del nombre/ID del rol. Las notas conservan lectura al alta; solo `admitted` y `temporarily_absent` aceptan nuevas notas. Reconciliar un INSERT incierto sobre nota ya existente debe reautorizar lectura y autoría exacta, pero nunca habilitar un INSERT nuevo por estar cerrada. La migración `20261013030000_context_note_insert_authorization_preflight.sql` valida autorización antes del lock para evitar revelar existencia durante el rechazo.

## Estado

Implementado en el corte mínimo: migraciones estructurales y guardas, generador de fixture reproducible, sincronización, pasarela `clinical-record`, contratos Dart tipados y vistas autorizadas de censo/ficha. La consulta móvil directa heredada se retiró. El fixture actual contiene 20 pacientes; el arranque `pnpm app:run` reutiliza/inicia Supabase y HAPI, re-aplica el transaction bundle con PUT sin borrar otros recursos, sincroniza vínculos y asignaciones y espera la función `clinical-record` antes de Flutter. En una base limpia se esperan 20 episodios: 14 abiertos (8 asignados y 6 sin asignar) y 6 cerrados históricos con `validUntil`. El arranque no purga recursos ni reemplaza asignaciones existentes: inserta una asignación solo si el par episodio/membresía no existe, por lo que tampoco renueva asignaciones históricas de pares existentes. Una asignación cerrada con `validUntil` vencido no concede por sí sola lectura clínica; el Administrador de demo puede leer episodios cerrados mediante sus permisos reservados y guardas RLS. No es ingesta clínica completa. HAPI aún opera sin autenticación: el compose local lo limita a loopback, pero el runtime de servidor legado escucha `0.0.0.0`; no declarar el riesgo de exposición cerrado fuera de esa configuración.
