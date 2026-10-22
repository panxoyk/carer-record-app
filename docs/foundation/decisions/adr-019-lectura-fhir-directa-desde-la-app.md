# ADR-019: Lectura directa de FHIR desde la app y bitácora enlazada

- Estado: Aceptada
- Fecha: 2026-10-21
- Alcance: demo sintética/local; lista de pacientes y ficha clínica leídas de un servidor FHIR R4 y enlace con la bitácora; no es una ingesta persistente ni admite datos reales
- Relación: **sustituye en parte a** ADR-004 (solo la exigencia de que FHIR se consuma únicamente desde una ingesta de servidor); conserva su principio de que dominio y UI no vean recursos FHIR. Depende de ADR-003, ADR-013, ADR-015, ADR-017 y ADR-018

## Contexto

ADR-004 decidió que FHIR vive en una frontera de ingesta del lado servidor, que valida y proyecta al modelo interno protegido por RLS y que Flutter nunca consulta el servidor FHIR. Ese pipeline sigue siendo un scaffold (EV-005). Para demostrar la integración con una FCE simulada, el equipo dispone de un servidor HAPI FHIR R4 con pacientes sintéticos y necesita que la app muestre la lista de pacientes y su ficha clínica completa, y que más adelante el modelo local reciba esa ficha una sección a la vez (ADR-017 y ADR-018).

La bitácora (ADR-015) y la autorización clínica (ADR-013) se apoyan en `hospitalizations` y `care_assignments` de Supabase. Un paciente que solo existe en el servidor FHIR no tiene hospitalización, así que no puede tener notas ni lectura autorizada por RLS.

## Decisión

1. **En la demo, Flutter lee el servidor FHIR directamente y solo con `GET`.** El cliente HTTP y el mapper viven en `data/` del dominio `fhir_record`; dominio y presentación solo ven entidades internas (`PatientSummary`, `ClinicalRecord`, `RecordEntry`). La frontera anticorrupción de ADR-004 se conserva dentro de la app. No hay escritura ni write-back.
2. **Contratos de lectura.** Lista: `GET [base]/Patient?_count=30&_sort=family`, con un parámetro `name` por palabra o `identifier`, paginada por `Bundle.link[relation=next]`. Ficha: `GET [base]/Patient/{id}/$everything` con la misma paginación. Los enlaces `next` se reescriben al host de la URL base. Se presentan ocho tipos: `Condition`, `AllergyIntolerance`, `MedicationRequest`, `Observation`, `Procedure`, `Immunization`, `DiagnosticReport` y `Encounter`; el resto se ignora sin proyectarse.
3. **La URL del servidor llega con `FHIR_BASE_URL`** (`--dart-define`, alimentado desde `.env` por `scripts/run-app.sh`). No hay credenciales FHIR en la app.
4. **La autorización de esta lectura es solo de interfaz.** El servidor de demostración no autentica y RLS no lo cubre. Las rutas `/patients` y `/fhir/` exigen `clinical.census.read` y `clinical.patient.read` en el router, y `clinical.timeline.read` decide si el paciente abre la bitácora o su información. La limitación se acepta únicamente para datos sintéticos y red local: el servidor no se expone fuera del equipo ni recibe datos reales (RK-031, Q-AUTH-03).
5. **La bitácora sigue en Supabase y se enlaza por identificadores derivados.** Un script de desarrollo (`scripts/fhir-sync`) lee los pacientes del servidor FHIR y crea, de forma idempotente, el paciente, la hospitalización, la ubicación vigente y las asignaciones asistenciales de demostración de Ana Torres y Matías Rojas. Copia solo lo que las pantallas de bitácora ya leen: nombre, nacimiento, sala, cama y fecha de ingreso. El id de la hospitalización se deriva del id numérico de FHIR (`f1000000-0000-0000-0000-` más el id con doce dígitos); el del paciente usa el prefijo `f0000000-`. `patients.external_reference` conserva `FHIR-<id>`. Las asignaciones masivas existen solo en este script local: no pertenecen a migraciones ni a seeds reutilizables.
6. **Servidor de demostración reproducible.** `docker/hapi-fhir` levanta HAPI FHIR con 10 pacientes ficticios, base en memoria y versión de imagen configurable.
7. **La ficha para el modelo local se entregará por sección.** La lectura con `$everything` es transitoria; la dirección es pedir cada tipo de recurso por separado y en paralelo, y entregarlo al modelo local de a una característica.
8. **Esta ADR no declara ingesta.** No hay raw privado, identidad compuesta, versionado, cuarentena ni checkpoints. El pipeline de ADR-004 sigue siendo la arquitectura objetivo para cualquier dato real.

## Alternativas consideradas

- **Mantener solo la ingesta de servidor (ADR-004):** es el camino correcto hacia producción, pero exige esquema raw, correspondencias y checkpoints antes de poder mostrar una ficha.
- **Guardar en Supabase solo el id y obtener el resto de FHIR:** evita duplicar nombres, pero obliga a modificar las pantallas y pruebas de la bitácora, hace una consulta FHIR extra por pantalla y no elimina la necesidad de crear hospitalización y asignación por paciente.
- **Crear la hospitalización desde la app al tocar un paciente:** requiere una función privilegiada que se salta la asignación de ADR-013.
- **Proxy o Edge Function que valide el JWT de Supabase delante del servidor FHIR:** da autorización de servidor, pero obliga a exponer el servidor local; queda como evolución (Q-AUTH-03).

## Consecuencias

- La app depende de la disponibilidad y la latencia del servidor FHIR. En la validación, `$everything` de un paciente con 646 recursos tardó cerca de 90 s.
- Conviven dos fuentes: FHIR para lista y ficha, Supabase para bitácora. La copia mínima puede divergir del servidor y se repite con `pnpm fhir:sync` tras cada `db:reset`.
- Se abre una superficie de lectura sin autorización de servidor.
- El módulo exige pruebas propias, que aún no existen.
- ADR-004 conserva vigencia como diseño de ingesta; esta ADR no lo reemplaza para datos reales.

## Riesgos

- RK-031: lectura sin autenticación de servidor.
- RK-032: divergencia de la copia mínima o interpretación como ingesta validada.
- RK-033: ficha lenta, truncada o simplificada por el mapper.
- RK-034: asignaciones masivas de demostración confundidas con el contrato de ADR-013.
- RK-035: resultados no reproducibles entre equipos.

## Evidencia y límites

- `app/lib/domains/fhir_record/`: cliente (`data/fhir_client.dart`), mapper (`data/fhir_mapper.dart`), entidades y regla de enlace (`domain/`) y pantallas (`presentation/fhir_record_screens.dart`).
- `app/lib/app/router/app_router.dart` y `navigation_policy.dart`: `/patients` y `/fhir/patients/:patientId` con guardas de interfaz.
- `scripts/fhir-sync/generate-sync.mjs` y `docker/hapi-fhir/`.
- Validación manual el 2026-10-21 en un Android real (Android 14) contra un HAPI FHIR en WSL2: lista paginada, búsqueda, ficha completa y apertura de la bitácora. Sincronización de 633 pacientes en Supabase local. En la misma fecha, `pnpm app:analyze` sin incidencias y `pnpm app:test` con 336 pruebas aprobadas y 1 omitida.
- Límites: el módulo no tiene pruebas automatizadas propias; el compose del servidor de demostración se comprobó con un servidor simulado, no con Docker real; no hay evidencia con otro servidor FHIR ni con datos reales; no se mide el rendimiento de la ficha por tipo de recurso.
