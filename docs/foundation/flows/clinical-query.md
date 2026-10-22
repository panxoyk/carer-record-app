# Flujo de consulta clínica

## Estado y objetivo

Subtarea 4.4 migra Flutter a contratos de lectura por hospitalización. La revisión integrada 4.5 y el gate final 5.2 se completaron para la demo sintética/local; el corte 3+4 se declara integrado solo dentro de ese alcance.

El gate de cierre 5.2 repitió validaciones locales con datos sintéticos y reset del stack desechable; no añade escritura clínica, lectura fuera de la asignación vigente ni despliegue productivo.

Desde 2026-10-21, en la demo sintética/local, la lista de pacientes de `/patients` proviene de un servidor FHIR y no del censo de Supabase (ver «Lista y ficha desde FHIR»). Los contratos de lectura por hospitalización siguen vigentes para la bitácora.

## Permisos y precondiciones

- El censo y la demografía mínima requieren `clinical.census.read` y `clinical.patient.read` efectivos en la organización seleccionada.
- La timeline requiere además `clinical.timeline.read`. RLS de PostgreSQL decide las filas; los guards son solo UX.
- El personal clínico requiere además asignación vigente exacta a la hospitalización. Los permisos y la organización seleccionada no sustituyen RLS.
- Las rutas de detalle usan `hospitalizationId`, nunca `patient_id` como frontera.

## Contratos de lectura

- `clinical_census_by_hospitalization`: columnas explícitas `organization_id,hospitalization_id,patient_id,hospitalization_status,admitted_at,discharged_at,unit_id,bed_label,given_name,family_name,birth_date`.
- `clinical_patient_demographics_by_hospitalization`: columnas explícitas `organization_id,hospitalization_id,patient_id,given_name,family_name,birth_date`.
- `clinical_timeline_by_hospitalization`: columnas explícitas `organization_id,hospitalization_id,event_id,kind,occurred_at,summary,patient_id,created_at`; filtra organización y hospitalización y ordena `occurred_at` descendente.

`patient_id` y `created_at` existen en el contrato de timeline vigente, pero el cliente no los usa para autorizar, correlacionar episodios ni presentar detalles. Ninguna vista expone `payload`, `recorded_by`, RUT, referencia externa o enum de practitioner.

## Presentación y autorización

- El censo busca localmente solo por nombre. Puede mostrar el `bed_label` autorizado; nunca presenta `unit_id` ni UUID. Sin ubicación autorizada muestra “Ubicación no registrada”.
- Detalle limitado a nombre, fecha de nacimiento y ubicación autorizada. Timeline consume `summary` como texto; no parsea JSONB.
- En 4.4 se retiraron deliberadamente los filtros de categorías de timeline para reducir estado de UI; el orden descendente lo establece el repositorio/PostgREST y la pantalla conserva el orden recibido.
- UUID manipulado, inexistente u oculto presenta el mismo estado neutro “Paciente no encontrado”. Una organización seleccionada determina el tenant; cambios de organización no reutilizan datos anteriores.
- Errores o respuestas vacías/denegadas eliminan el contenido visible; no hay fallback stale ni caché persistente.

## Q-AUTH-02

Providers clínicos `autoDispose` dependen de sesión y `iamContextProvider`. Entrar a censo, detalle o timeline invalida autorización y datos una vez; pull-to-refresh vuelve a consultar y reemplaza el estado. El observer global `resumed` invalida contexto IAM y providers clínicos. El cambio de organización y mutaciones IAM también invalidan estas fuentes.

Una revocación remota surte efecto en la siguiente consulta PostgreSQL; no se promete retirada push mientras la pantalla permanece inmóvil. Loading, empty, not-found, error y denied nunca conservan contenido anterior como fallback. RLS es la autoridad final.

## Lista y ficha desde FHIR (demo, ADR-019)

### Alcance

La ruta `/patients` presenta la lista de pacientes de un servidor FHIR R4 (`FhirPatientListScreen`). El censo de Supabase (`PatientsScreen`) permanece en el código sin ruta. Al tocar un paciente se abre la bitácora de su hospitalización de Supabase, con los contratos de lectura anteriores. La ficha clínica completa de FHIR existe en `/fhir/patients/:patientId`, pero la lista no enlaza con ella.

### Permisos y autorización

- `/patients` y `/fhir/` exigen `clinical.census.read` y `clinical.patient.read` en el router. Son guardas de interfaz.
- `clinical.timeline.read` decide si el toque abre la bitácora o la pantalla de información del paciente.
- El servidor FHIR no autentica ni aplica RLS: la lista y la ficha no están protegidas por asignación asistencial. Se acepta solo con datos sintéticos y red local (RK-031, Q-AUTH-03). La bitácora sí conserva RLS y asignación vigente.

### Ubicacion contratos de lectura

Las interacciones, el mapeo y sus pérdidas están en la sección 15 de [Integración FHIR R4](../06-fhir-integration.md).

### Presentación

- La lista pagina de a 30 al hacer scroll y se recarga con pull-to-refresh. La búsqueda se hace en el servidor, por nombre (cada palabra cuenta) o por identificador.
- Cada fila muestra nombre, edad, sexo, sala y cama. No muestra identificadores de negocio.
- La ficha agrupa por tipo, ordena por fecha descendente y avisa cuando está incompleta. Carga, vacío y error tienen estado propio con reintento.
- El tiempo de espera es de 20 s para la lista y de 180 s por página de ficha.

### Enlace con la bitácora

El id de la hospitalización se deriva del id numérico de FHIR (sección 15.4 de la integración). Si la fila no existe en Supabase, la bitácora muestra el estado neutro «Paciente no encontrado»; no hay creación automática. El script `pnpm fhir:sync` crea las filas y debe repetirse tras cada `db:reset`.

## Evidencia y límites

Modelos: `app/lib/domains/patient/data/models/patient_model.dart` y `app/lib/domains/clinical_event/data/models/clinical_event_model.dart`. Repositorios y providers: `patient_repository.dart`, `clinical_event_repository.dart`, `patient_providers.dart` y `clinical_event_providers.dart`. UI: `patient_screens.dart`; router: `app/lib/app/router/app_router.dart`. El refresh/lifecycle de autorización se compone desde `app/session/`; no cambia contratos de lectura clínica ni permisos.

La cobertura incluye parsing tipado, búsqueda por nombre, ubicación segura, estado neutral y resumen tipado. La integración local comprueba censo, vista demográfica específica y timeline por `organization_id` + `hospitalization_id`, UUID manipulado y revocación con el mismo JWT clínico; Flutter tiene cobertura widget/modelo dirigida. La verificación es solo para demo sintética/local: no acredita concurrencia entre dos sesiones, producción ni datos reales.

Para la lista y la ficha de FHIR: `app/lib/domains/fhir_record/` y las rutas de `app_router.dart`. La verificación es manual, en un Android real contra un HAPI en WSL2, el 2026-10-21; no existen pruebas automatizadas del módulo. La ficha de un paciente de 646 recursos tardó cerca de 90 s con `$everything`, y no se ha medido la consulta por tipo de recurso.
