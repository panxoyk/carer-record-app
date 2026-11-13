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
{
  "organizationId": "uuid",
  "hospitalizationId": "uuid",
  "purpose": "record",
  "range": {
    "fromUtc": "2026-10-20T00:00:00Z",
    "toUtc": "2026-10-21T00:00:00Z"
  }
}
```

`range` es opcional. Si se omite, la consulta mantiene el comportamiento previo de ficha/timeline completos del paciente/episodio. Si se incluye, contiene exactamente instantes UTC `fromUtc` y `toUtc`, con inicio menor que término y término no futuro. La Edge no recibe una zona horaria en el request. Para este MVP local y sintético, `clinical-record` interpreta fechas FHIR date-only en la zona fija `America/Santiago`; nunca usa un offset fijo como UTC-3. El contexto RPC sigue validando tenant y episodio autorizado, pero no provee la zona usada por el filtro. Los recursos sin fecha soportada quedan fuera del rango. `dateFor` admite `effectiveDateTime`, `effectiveDate`, `issued`, `authoredOn`, `performedDateTime`, `performedPeriod.start`, `onsetDateTime`, `recordedDate` y `date`; una variante de perfil no soportada cae en la regla de fecha ausente, no se adivina. El límite existente de 500 recursos y el estado parcial/truncado se mantienen sin cambios.

Respuesta tipada: `{status: "complete"|"partial", truncated: boolean, freshness: {retrievedAt: string, sourceUpdatedAt: string|null}, patient: {id: string, name: string, identifier: string|null, birthDate: string|null, gender: string|null}, hospitalization: {id: string, status: string, admittedAt: string, dischargedAt: string|null, unit: string|null, bed: string|null}, sections: [{type: string, entries: [{id: string, title: string, detail: string|null, date: string|null, isDateOnly: boolean, sourceKind: string}]}], timeline: [{id: string, occurredAt: string|null, precision: string|null, resourceType: string, title: string, detail: string|null}]}`. ADR-024 amplía este contrato: entradas con `value`, `flag`, `code`, `category`, `administeredAt` y `noteRef`; secciones `administrations` y `photos`; episodio con `attendingPhysician` y `reason`; propósito `attachment` para descargar una foto, y la función de escritura `clinical-attachment`.

`patient.id` es el ID interno; cada `sourceKind`/ID de entrada identifica la fuente como `demo-hapi/<type>/<id>`. Los IDs de entradas/timeline son estables por fuente y recurso. No se retorna JSON FHIR crudo. La pasarela obtiene URL y credenciales exclusivamente de configuración servidor.

La consulta de censo/lista usa la vista `fhir_clinical_census_by_hospitalization` y RLS. `record` requiere `clinical.census.read` y `clinical.patient.read` más autorización exacta del episodio por la ruta `clinical.assigned.read`/membresía/helper; `timeline` exige además `clinical.timeline.read`. La excepción existente de Administrador demo conserva `clinical.organization.read`, alcance y guardas RLS; no depende del nombre/ID del rol. Las notas conservan lectura al alta; solo `admitted` y `temporarily_absent` aceptan nuevas notas. Reconciliar un INSERT incierto sobre nota ya existente debe reautorizar lectura y autoría exacta, pero nunca habilitar un INSERT nuevo por estar cerrada. La migración `20261013030000_context_note_insert_authorization_preflight.sql` valida autorización antes del lock para evitar revelar existencia durante el rechazo.

## Estado

Implementado en el corte mínimo: migraciones estructurales y guardas, generador de fixture reproducible, sincronización, pasarela `clinical-record`, contratos Dart tipados y vistas autorizadas de censo/ficha. La consulta móvil directa heredada se retiró. El fixture actual contiene 20 pacientes; `pnpm env:up` reutiliza/inicia Supabase y HAPI, ejecuta bootstrap create-only y crea observaciones diarias sin borrar recursos existentes, sincroniza vínculos y asignaciones y sirve `clinical-record` en foreground. `pnpm app:run` solo inicia Flutter. En una base limpia se esperan 20 episodios: 14 abiertos (8 asignados y 6 sin asignar) y 6 cerrados históricos con `validUntil`. `env:up` no purga recursos ni reemplaza asignaciones existentes: inserta una asignación solo si el par episodio/membresía no existe, por lo que tampoco renueva asignaciones históricas de pares existentes. `env:stop` valida el datasource y volumen persistente, desconecta HAPI de la red Supabase y detiene HAPI/Supabase sin eliminar volúmenes; un HAPI legado incompatible se rechaza sin detenerlo. Una asignación cerrada con `validUntil` vencido no concede por sí sola lectura clínica; el Administrador de demo puede leer episodios cerrados mediante sus permisos reservados y guardas RLS. No es ingesta clínica completa. HAPI aún opera sin autenticación: el compose local lo limita a loopback, pero el runtime de servidor legado escucha `0.0.0.0`; no declarar el riesgo de exposición cerrado fuera de esa configuración.

La lectura acotada por rango UTC conserva las mismas reglas de autorización y solo filtra la respuesta; no concede acceso adicional. Los resúmenes históricos guardan su zona de generación y nunca se reescriben; el contrato actual de resumen exige `America/Santiago` y falla explícitamente ante discrepancia, sin modificar seed ni migraciones. El contexto de resumen puede devolver la zona organizacional mediante su RPC autorizada para comprobar ese contrato, sin una llamada de red adicional; la organización de demo está sembrada con `America/Santiago`. La zona organizacional dinámica sigue siendo la dirección objetivo para un futuro alcance multiinstitución, no el contrato de este MVP local/sintético.

El arranque de HAPI usa H2 persistente en `/data/hapi` del volumen `carer-record-hapi-data`, preparación de permisos con imagen Alpine fijada y UID/GID `65532:65532`. El bootstrap Node del host crea únicamente identidades ausentes y depende del comportamiento verificado en HAPI 8.12: `PUT` con `If-Match: W/"0"`; no equivale a migrar un HAPI existente. La exportación/restauración es archivo de recursos FHIR para transición manual, no respaldo íntegro de base ni garantía de preservar historia/versionIds o tombstones.
