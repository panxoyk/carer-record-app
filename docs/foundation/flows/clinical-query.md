# Flujo de consulta clínica

## Estado y objetivo

Subtarea 4.4 migra Flutter a contratos de lectura por hospitalización. La revisión integrada 4.5 y el gate final 5.2 se completaron para la demo sintética/local; el corte 3+4 se declara integrado solo dentro de ese alcance.

El gate de cierre 5.2 repitió validaciones locales con datos sintéticos y reset del stack desechable; no añade escritura clínica, lectura fuera de la asignación vigente ni despliegue productivo.

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

## Evidencia y límites

Modelos: `app/lib/domains/patient/data/models/patient_model.dart` y `app/lib/domains/clinical_event/data/models/clinical_event_model.dart`. Repositorios y providers: `patient_repository.dart`, `clinical_event_repository.dart`, `patient_providers.dart` y `clinical_event_providers.dart`. UI: `patient_screens.dart`; router: `app/lib/app/router/app_router.dart`. El refresh/lifecycle de autorización se compone desde `app/session/`; no cambia contratos de lectura clínica ni permisos.

La cobertura incluye parsing tipado, búsqueda por nombre, ubicación segura, estado neutral y resumen tipado. La integración local comprueba censo, vista demográfica específica y timeline por `organization_id` + `hospitalization_id`, UUID manipulado y revocación con el mismo JWT clínico; Flutter tiene cobertura widget/modelo dirigida. La verificación es solo para demo sintética/local: no acredita concurrencia entre dos sesiones, producción ni datos reales.
