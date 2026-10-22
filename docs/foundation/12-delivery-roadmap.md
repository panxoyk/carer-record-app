# Roadmap de entrega vertical

## Enfoque

El roadmap organiza trabajo en cortes verticales demostrables, no en capas técnicas aisladas. Cada corte incorpora autorización, datos, procesamiento, interfaz mínima, observabilidad, pruebas y documentación necesarias para un flujo extremo a extremo. No asigna fechas ni promete despliegue productivo.

La fotografía previa a esta fundación registra un MVP local con autenticación, administración y timeline clínico de solo lectura (`baseline/carer-record-app.md:9-13`). El pipeline ejecutable informa que la ingesta FHIR está diferida (`scripts/data_pipeline/main.py:9-15`). Todo corte posterior se considera **propuesto** hasta que su criterio de salida tenga evidencia en el repositorio.

## Reglas de avance

- No comenzar un corte que use PHI/IPS real; el prototipo opera con sintéticos.
- Resolver decisiones bloqueantes antes de persistir nuevas categorías de datos.
- Implementar primero autorización y constraints, luego repositorios/servicios y finalmente UI.
- Una demo no equivale a terminado: deben pasar pruebas de denegación, fallo, retry y cleanup.
- Cada corte actualiza trazabilidad, riesgos, preguntas y evidencia.
- Evitar infraestructura anticipada: outbox, caché o proveedor se incorporan cuando el corte los necesita.
- Los turnos quedan fuera de alcance conforme a ADR-012.

## Estado y secuencia

| Corte | Resultado demostrable                                       | Estado documental               | Dependencias                                |
| ----- | ----------------------------------------------------------- | ------------------------------- | ------------------------------------------- |
| V0    | Baseline local reproducible y límites declarados            | Parcialmente evidenciado        | Ninguna                                     |
| V1    | FHIR sintético validado llega a timeline                    | Propuesto; demo directa parcial | V0, ADR-004                                 |
| V2    | Permisos configurables y asignación gobiernan lectura       | Parcial; corte incompleto       | V0, ADR-005/013 y hospitalizaciones mínimas |
| V3    | Audio sintético se captura, transcribe localmente y elimina | Parcial; SP-01 abierto          | V0, ADR-006/007/010/016                     |
| V4    | UI NER local señala entidades sin alterar el texto          | Pendiente                       | V3, ADR-017                                 |
| V5    | Síntesis local asistida en dispositivo                      | Parcial; benchmark pendiente    | ADR-017/018                                 |
| V6    | Resumen temporal versionado usa caché segura                | Pendiente                       | V1, V5, ADR-011                             |
| V7    | Eliminación, auditoría y outbox resisten fallos             | Propuesto                       | V2-V6                                       |
| V8    | Evaluación académica reproducible y cierre de brechas       | Propuesto                       | V1-V7                                       |

V1 y V3 pueden explorarse en paralelo mediante spikes, pero no compartir contratos inestables. La antigua dependencia cloud de síntesis quedó sustituida por ADR-017; el benchmark sintético de la síntesis local sigue pendiente.

El corte de hitos ([ADR-015](decisions/adr-015-hitos-bitora-audio.md), sustituida en parte por ADR-016) añade escritura confirmada de `context_notes` bajo RLS y recorrido móvil. El audio almacenado en bucket fue retirado; se publica solo el texto confirmado. Esto no completa V3: la decodificación ASR real y SP-01 siguen abiertos, y la UI NER permanece pendiente.

El corte de lectura directa de FHIR ([ADR-019](decisions/adr-019-lectura-fhir-directa-desde-la-app.md), 2026-10-21) adelanta, solo para la demo sintética/local, parte del valor de V1: la app lista pacientes y muestra su ficha leyendo un servidor FHIR, y cada paciente se enlaza con la bitácora de Supabase. No cumple V1: no hay procedencia, identidad compuesta, idempotencia, cuarentena ni matriz de mapping completa, y la lectura no tiene autorización de servidor. Quedan pendientes las pruebas del módulo, la ficha por tipo de recurso y su entrega al modelo local por sección.

El subcorte DB de V2 implementa IAM, hospitalizaciones/asignaciones y RLS clínico por episodio. Los subcortes 4.1 (operaciones IAM), 4.2 (alta institucional Edge), 4.3 (administración institucional Flutter y asignaciones asistenciales) y 4.4 (consulta clínica Flutter por hospitalización) tienen implementación y pruebas dirigidas. La revisión integrada 4.5 y el gate 5.2 están cerrados para demo sintética/local; esto no completa V2 ni acredita producción. Fases 3 y 4 solo se consideran integradas dentro de ese alcance.

## V0 - Baseline y guardrails

**Valor:** una persona evaluadora puede levantar el entorno y observar los límites del prototipo sin asumir capacidades inexistentes.

**Alcance:** reproducibilidad local, seed sintético, autenticación, roles del baseline, lectura clínica, CI y documentación de decisiones. La fotografía registra consumo de clave publishable (`app/lib/core/network/supabase_client.dart:4-15`), RLS en tablas clínicas (`supabase/migrations/20260910000000_initial_clinical_schema.sql:41-47`) y pruebas que restringen la matriz (`supabase/tests/patients_rls.test.sql:29-169`).

**Criterios de salida:**

- setup local y CI pasan desde un checkout limpio;
- las limitaciones académicas y de datos sintéticos son visibles;
- ADR-001 a ADR-015 y apéndices están enlazados;
- no hay secretos ni datos reales versionados;
- riesgos P0 tienen tratamiento o bloqueo explícito.

## V1 - Frontera FHIR a timeline

**Estado:** Propuesto. La lectura directa de la demo (ADR-019) no lo completa: no ingiere, no conserva procedencia y no tiene autorización de servidor.

**Valor:** un Bundle o conjunto mínimo de recursos FHIR sintéticos soportados produce pacientes y eventos internos consultables.

**Incluye:** versión/perfiles explícitos, fixtures, validación, mapping, procedencia, identidad externa, upsert idempotente, cuarentena y visualización del resultado. La frontera impide que tipos FHIR atraviesen el dominio móvil.

**Entidades:** `Patient`, `ClinicalEvent` existentes; se proponen `IngestionRun`, `SourceResource` y `MappingError` solo si el corte demuestra necesitarlos.

**Pruebas:** mappings válidos e inválidos, referencias fuera de orden, timestamps, replay, actualización y E2E F-04→F-03.

**Criterio de salida:** reingerir el mismo fixture no duplica; un recurso inválido no modifica parcialmente el timeline; la matriz de mapping y pérdidas está documentada.

## V2 - Permisos configurables

**Valor:** una persona administradora autorizada compone permisos y asigna hospitalizaciones sintéticas; RLS permite al Personal clínico leer solo sus episodios vigentes sin despliegue SQL.

**Incluye:** catálogo cerrado de permisos, dos roles seed, hospitalizaciones mínimas y `care_assignments`, estado/vigencia, administración mínima y auditoría. La matriz estática del baseline (`supabase/migrations/20260910100000_patient_read_access.sql:10-16`) se migra de forma aditiva. Personal clínico requiere asignación vigente; el Administrador de demo usa `clinical.organization.read` reservado, permisos concretos y RLS. No depende de completar V1 ni de la ingesta FHIR completa.

**Entidades:** `organizations`, `units`, `profiles`, `organization_memberships`, `roles`, `permission_catalog`, `role_permissions`, `role_assignments`, `hospitalizations` y `care_assignments`. La ingesta FHIR completa puede seguir pendiente; V2 solo adelanta las hospitalizaciones mínimas definidas por ADR-013.

**Pruebas:** pgTAP de permiso reservado no delegable, bootstrap/último Administrador, grant/revoke/suspensión/Administrador de demo/sin perfil, Personal clínico asignado/no asignado, alta/cancelación/corrección, traslado, múltiples episodios, tenant ajeno, concurrencia e invalidación de sesión según contrato.

**Criterio de salida:** denegación por defecto permanece; ninguna edición de UI agrega autoridad; todas las combinaciones soportadas tienen casos positivos y negativos.

## V3 - Captura y ASR local con borrado

**Valor:** con audio estrictamente sintético, una persona captura una muestra, obtiene una transcripción técnica local verificable y elimina el artefacto; la experiencia final de usuario revisará audio y síntesis en V5.

**Incluye:** permiso de micrófono, consentimiento/indicador, límites, archivo temporal, motor ASR local detrás de interfaz, procedencia del modelo, estados y borrado idempotente. No incluye nube. El audio de hitos ya no tiene contrato de bucket: ADR-016 lo retiró. Actualmente hay captura/flujo de revisión, cleanup básico probado y prueba de motor nativo condicionada a pesos y WAV sintético; la decodificación real no está validada y SP-01 sigue abierto.

**Entidades locales:** `DictationSession`, `AsrTranscript`, `DraftVault`; en servidor solo `context_notes` con el texto confirmado y su procedencia técnica.

**Pruebas:** SP-01, permisos, interrupciones, crash/restart, espacio insuficiente, checksum de modelo, ausencia de tráfico de audio y la prueba de privacidad de pgTAP. No se afirma equivalencia nativa a partir de fakes.

**Criterio de salida:** el dispositivo objetivo cumple presupuesto académico documentado; no existe fallback cloud; una operación de borrado repetida deja cero artefactos observables dentro del alcance probado.

## V4 - NER local sin tokenización

**Estado:** Requisito decidido; UI pendiente. La tokenización reversible quedó sustituida por ADR-017: al no salir texto del dispositivo no hay mapa que custodiar. Queda implementar la señalización local de entidades.

**Valor:** una transcripción o un hito sintético muestran al autor las entidades que el modelo local detecta, sin modificar el texto y sin construir ningún mapa.

**Incluye:** taxonomía, offsets, límites por clase y visibilidad de la incertidumbre. NER no se presenta como anonimización.

**Entidades:** `DetectedEntity` como resultado local del puerto `SynthesisProvider`; sin `TokenizedDocument` ni `TokenMap`. El caso de uso existe, pero la UI que muestra las entidades aún no está entregada.

**Pruebas:** SP-02, solapamientos, Unicode, falsos negativos críticos y textos íntegramente sintéticos.

**Criterio de salida:** el texto del autor nunca se sustituye y no existe ningún artefacto capaz de reconstruir entidades fuera del dispositivo.

## V5 - Síntesis local con modelo en el dispositivo

**Estado:** Decidido e implementado parcialmente en alcance local; ADR-017 sustituyó la síntesis cloud. Los casos de uso y controladores existen; el benchmark sintético y la validación nativa de rendimiento siguen pendientes.

**Valor:** una persona escribe un hito a mano y obtiene opcionalmente una mejor redacción generada en su propio teléfono, que siempre revisa antes de confirmar.

**Incluye:** `on_device_ai` y sus adaptadores; los casos de uso/controladores permanecen en `context_note`, con fake determinista, timeout, cancelación lógica, códigos de error e instalación/verificación del modelo. `LocalCapabilityRepository` es la única frontera de provisioning; los leases son genéricos. No incluye proveedor cloud, Edge Function ni guard de procedencia. La cancelación late-result no afirma detener nativamente el motor.

**No incluye:** bloqueo de la publicación. Si el motor falla o el modelo no está instalado, el hito se publica tal cual.

**Pruebas:** casos de uso con fake, límites, ausencia de modelo y cancelación; benchmark sobre corpus sintético pendiente. No se afirma equivalencia funcional del adaptador nativo desde tests de fake.

**Criterio de salida:** el dominio no importa SDK ni tipos del runtime; cambiar el fake por el adaptador no cambia el caso de uso; ningún texto sale del dispositivo; un hito se publica incluso con el modelo ausente.

## V6 - Resumen temporal y caché

**Valor:** la persona consulta un resumen sintético de una ventana temporal y una segunda lectura reutiliza solo una entrada exactamente vigente.

**Incluye:** rango `[desde, hasta)`, zona horaria, conjunto/versiones fuente, versión de modelo y prompt, estado, expiración e invalidación. La respuesta indica procedencia, ventana y que no sustituye la ficha.

**Entidades:** `SummaryRequest`, `SummarySnapshot` y `SummaryCacheEntry`, que pueden consolidarse si no compromete auditoría.

**Pruebas:** bordes temporales, zona horaria, hit/miss, cambio de fuente, aislamiento RLS, concurrencia, timeout y respuesta vacía.

**Criterio de salida:** una mutación o nueva versión fuente invalida el resultado; jamás se devuelve caché de otro paciente o ventana; la Edge Function `clinical-summary` del baseline ya no existe (ADR-017).

## V7 - Ciclo operacional: outbox, auditoría y eliminación

**Valor:** los efectos críticos son trazables y recuperables sin conservar contenido innecesario.

**Incluye:** eventos de auditoría mínimos, outbox transaccional, worker idempotente, retries, dead-letter, barrido de retención y evidencia de borrado. Se aplica primero a un flujo crítico y luego se extiende.

**Pruebas:** crash entre commit y publicación, workers concurrentes, replay, poison message, TTL, autorización de auditoría y ausencia de PHI en payload/log.

**Criterio de salida:** una demo de fault injection recupera el efecto sin duplicarlo; cada eliminación registra resultado sin contenido; existe runbook académico de recuperación.

## V8 - Evaluación y cierre académico

**Valor:** resultados y límites son reproducibles y auditables por la evaluación, sin presentarse como validación productiva.

**Incluye:** protocolo, hardware, versiones, corpus sintético, métricas, resultados negativos, amenazas a validez, demos E2E y backlog de producción separado.

**Criterios de salida:**

- trazabilidad RQ→ADR→flujo→entidad→prueba completa para el alcance implementado;
- riesgos residuales y preguntas sin resolver explícitos;
- resultados de spikes reproducibles;
- ninguna afirmación excede la evidencia;
- turnos y capacidades productivas siguen identificados fuera de alcance.

## Trabajo explícitamente no incluido

- gestión de turnos, calendario, asistencia o handoff operativo;
- recomendación, diagnóstico o decisión clínica automatizada;
- soporte FHIR universal;
- datos reales, despliegue productivo, SLA, alta disponibilidad o disaster recovery;
- certificación regulatoria, legal, de seguridad o eficacia clínica;
- analítica secundaria, entrenamiento de modelos o reutilización de datos.

Estos límites derivan de [ADR-002](decisions/adr-002-prototipo-academico.md) y [ADR-012](decisions/adr-012-turnos-fuera-de-alcance.md).

## Control de entrega

Cada corte debe añadir una fila o actualizar estado en [requirements-traceability.md](appendices/requirements-traceability.md), registrar evidencia en [evidence-index.md](appendices/evidence-index.md), cerrar o reformular preguntas y revisar [risk-register.md](appendices/risk-register.md). La etiqueta **implementado** solo se usa cuando código y pruebas existen; **validado** requiere además que los criterios del corte se hayan ejecutado en el entorno declarado.

El gate 5.2 aquí registrado cierra la evidencia local sintética de las fases 3+4 y la revisión de controles; no inicia V5 ni declara V2 completo o el sistema desplegable en producción. La carrera de dos sesiones del último Administrador permanece pendiente y no se habilita ninguna capacidad futura o productiva.
