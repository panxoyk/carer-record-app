# Estrategia de testing y validación

## Objetivo

La validación debe producir evidencia proporcionada al riesgo del prototipo, especialmente en autorización, privacidad, transformación clínica e idempotencia. No demuestra seguridad o eficacia clínica productiva. Una prueba automatizada confirma un contrato bajo condiciones conocidas; no reemplaza revisión jurídica, clínica, de usabilidad o seguridad independiente.

La suite histórica del baseline protegía RLS, privilegios SQL y enmascaramiento de RUT; la consulta actual no transporta identificadores completos. El workflow observado levanta Supabase, reconstruye la base, ejecuta lint y pgTAP y luego valida Flutter (`.github/workflows/verify.yml:19-35`). La fotografía no contiene implementación ni evidencia para audio, FHIR, ASR, NER, síntesis, caché, outbox o E2E.

## Principios

- Probar primero la frontera de mayor autoridad: Postgres/RLS antes que guards de UI.
- Asociar cada prueba a un requisito y riesgo, no a una meta de cobertura porcentual.
- Combinar caso permitido, denegado, límite, reintento y fallo parcial donde corresponda.
- Usar únicamente datos sintéticos; un fixture tokenizado no se presume anónimo.
- Hacer fixtures deterministas, versionados y sin dependencia del orden de ejecución; cada prueba crea y elimina su estado o usa una transacción con rollback.
- Verificar resultados observables e invariantes, no detalles incidentales.
- Añadir regresiones para bugs de autorización, privilegios, privacidad o integridad en la capa de menor autoridad que pueda demostrarlos.
- Actualizar la prueba cuando cambie intencionalmente un contrato protegido; un refactor interno no debe obligar a modificarla.
- Mantener separadas validación técnica, evaluación de modelo y aceptación clínica.
- Registrar versión de esquema, fixture, modelo y proveedor para reproducibilidad.

## Capas y responsabilidades

| Capa                   | Contratos a validar                                        | Herramienta objetivo                                   | Estado actual              |
| ---------------------- | ---------------------------------------------------------- | ------------------------------------------------------ | -------------------------- |
| Postgres/RLS           | permisos, estados, privilegios, constraints, outbox, caché | pgTAP y reset local                                    | Parcialmente implementada  |
| Flutter dominio        | reglas de privacidad, estados y transformaciones puras     | `flutter_test`                                         | Mínima                     |
| Flutter integración/UI | captura, errores, navegación crítica y borrado             | fakes deterministas, widget/integration test selectivo | No implementada            |
| Edge Functions         | authn/authz, esquema, idempotencia, sanitización y fallos  | tests Deno/HTTP contra local                           | Solo format/lint/typecheck |
| Frontera FHIR          | perfiles, mappings, referencias y rechazo                  | fixtures y contract tests                              | Scaffold sin ingesta       |
| ASR/NER                | exactitud, latencia, falsos negativos y reversibilidad     | corpus sintético versionado                            | No implementada            |
| Proveedor cloud        | contrato abstracto, timeout, retry y payload sintético     | fake + sandbox solo sintético                          | No implementada            |
| E2E                    | cortes verticales y aislamiento entre actores              | Supabase local + app/emulador                          | Manual y parcial           |
| Spikes                 | factibilidad y límites, sin compromiso productivo          | protocolo reproducible                                 | Pendiente                  |

El baseline fechado en esta fundación constata que todavía no existen tests HTTP, widget ni mappings. Las pruebas adicionales solo se incorporan al implementar los nuevos flujos de alto riesgo; no convierten retrospectivamente las capacidades futuras en existentes.

## pgTAP y base de datos

Cada migración que cambie autorización, entidad sensible, outbox o caché debe incluir pruebas dentro de una transacción con rollback. La prueba debe ejecutar como `anon`, `authenticated` u otro rol real, fijando claims explícitos.

Las migraciones de backfill IAM se validan además con `pnpm db:upgrade:test`: un proyecto Supabase desechable aplica la cadena baseline, inserta practitioners exclusivamente sintéticos antes de fase 1, aplica las migraciones IAM y verifica el backfill y su idempotencia. Este escenario es independiente de `pnpm db:reset` y no utiliza la base local habitual.

El harness aplica fases 2.1, 2.2, 3.1 y 3.2 después de IAM. `supabase/tests/clinical_rls_phase3.test.sql` verifica desaparición de helpers/policies legacy, grants sensibles, ausencia de INSERT/UPDATE/DELETE/TRUNCATE para `authenticated` y `service_role`, bridge propietario controlado, contratos exactos de vistas, permiso acumulativo para demografía, tenant, asignación por episodio, estados futuro/vencido/revocado, suspensión, episodios múltiples y revocación en sesión; `patients_rls.test.sql` trata las filas sin enlace como ocultas. La migración `20261011280000_harden_clinical_runtime_writes_and_views.sql` añade esas defensas y completa censo/timeline. La subtarea Flutter 4.4 consume los contratos; la integración 4.5 fue revisada y el gate 5.2 la cerró para demo sintética/local. La concurrencia de dos sesiones permanece sin probar.

### Matriz mínima por recurso sensible

- anónimo: no puede leer ni mutar;
- sesión válida sin perfil: no obtiene autoridad clínica;
- practitioner activo con permiso: solo ejecuta la operación concedida;
- practitioner activo sin permiso: denegado aunque conozca el ID;
- cuenta suspendida: denegada inmediatamente;
- administrador sin `clinical.organization.read`: no hereda acceso clínico; Administrador de demo con permiso reservado y permisos concretos: solo su tenant;
- Service Role: se usa solo en test servidor explícito, nunca como sustituto de casos RLS;
- pertenencia: un sujeto autorizado para A no observa B cuando exista segmentación;
- mutación: `insert`, `update` y `delete` se prueban por separado;
- funciones: `public` y `anon` no ejecutan helpers internos o privilegiados.

Los tests actuales proporcionan ejemplos: casos anónimo y sin perfil (`supabase/tests/patients_rls.test.sql:29-54`), roles clínicos y administrador sin acceso implícito (`supabase/tests/patients_rls.test.sql:56-116`), suspendido y denegación de mutaciones (`supabase/tests/patients_rls.test.sql:118-169`), y privilegios de funciones (`supabase/tests/function_privileges.test.sql:7-44`).

### Permisos configurables

Al implementar ADR-005 y ADR-013, pgTAP debe probar concesión, revocación, vigencia temporal, conflicto entre grants, suspensión y ausencia de fila. Debe demostrar que `clinical.organization.read` solo puede estar en el rol protegido, no se copia ni delega a roles clínicos ordinarios y RLS no decide por nombre/ID. También debe probar Personal clínico asignado/no asignado, alta con lectura histórica, cancelación/invalidación, corrección sin herencia, traslado, bootstrap/último Administrador y revocación efectiva en una sesión ya iniciada.

La mutabilidad de roles se verifica por separado de la composición. Un rol de configuración del tenant admite composición, renombrado y desactivación; el rol con `protected_kind` rechaza las tres; un rol marcado `is_system` pero no protegido admitiría composición y rechazaría renombrado y desactivación. En todos los casos el permiso reservado se rechaza y la composición persistida coincide con la solicitada.

### Caché y outbox

Probar restricciones únicas para claves de idempotencia, aislamiento por paciente, transición válida de estados, reclamación concurrente por un solo worker, reintento con backoff, dead-letter y ausencia de payload clínico no autorizado. Para caché, probar hit exacto, miss por versión/modelo, invalidación por cambio de fuente, expiración y RLS.

## Flutter

### Pruebas unitarias

Cubrir reglas públicas y estables: contratos tipados por hospitalización, búsqueda de censo solo por nombre, ubicación sin UUID, summary tipado, invalidación y estados que retiran contenido previo. Para la gestión de asignaciones, cubrir el contrato histórico de nombre/estado de membresía del asignado, elegibilidad activa para nuevas concesiones, filtro local por nombre de paciente autorizado o UUID de episodio y presentación institucional sin segundos de asignaciones actuales e históricas. Las antiguas pruebas de enmascaramiento/búsqueda de RUT ya no representan el producto y fueron sustituidas por reglas de minimización.

Nombrar cada test por su resultado observable y condición, mantener una regla por test y usar fixtures locales válidos que sobrescriban solo el dato relevante. Evitar mocks, setup y helpers compartidos cuando un fixture local resulte más claro.

La navegación debe verificar que `/` dirige a `/patients` a los usuarios con permisos clínicos efectivos y a `/settings` cuando no los tienen. Verificar también que las entradas de administración institucional en ajustes son independientes, aparecen según permisos efectivos, se ocultan cuando el usuario no tiene ninguno, y que la sección no concede autoridad.

### Pruebas de widget e integración selectivas

Añadirlas solo para riesgos del nuevo flujo:

- indicador visible y estado de consentimiento durante grabación;
- interrupción, cancelación y falta de permiso de micrófono;
- borrado de temporales tras éxito, cancelación, crash simulado y retry;
- distinción visible entre transcripción, borrador y resumen;
- imposibilidad de activar proveedor cloud con dataset no sintético;
- estados de carga, error y retry sin duplicar efectos;
- sesión suspendida o revocada durante una operación.

Inyectar repositorios, reloj, filesystem, ASR y proveedor como fakes; no usar red real en unit/widget tests. Las pruebas E2E sí pueden usar Supabase local con seed sintético.

## Edge Functions

El baseline solo exigía formato, lint y typecheck (`package.json:21-26`). La Edge Function `clinical-summary` solo autenticaba y devolvía `501`, y ADR-017 la retiró al dejar la síntesis en el dispositivo; `create-practitioner` es hoy la única función y ya tiene tests de handler. Antes de considerar implementada una función nueva se requieren tests HTTP para:

- método, content type, cuerpo ausente/malformado/sobredimensionado;
- JWT ausente, inválido, expirado y usuario inexistente;
- autorización denegada aun con JWT válido;
- respuesta estable sin detalles ni secretos;
- timeout, cancelación y error del proveedor;
- clave de idempotencia repetida y concurrente;
- retry solo de fallos transitorios;
- compensación o outbox ante fallo parcial;
- logs sanitizados y correlation ID propagado;
- rechazo técnico de contenido no sintético en la integración cloud del prototipo.

Los tests deben usar Supabase local y secretos exclusivos de test. Nunca imprimir Service Role ni cuerpos sensibles.

## Mappings y frontera FHIR

El pipeline del baseline era solo un scaffold que informaba que la ingesta estaba diferida (`scripts/data_pipeline/main.py:1-15`). ADR-004 exige una frontera versionada. La estrategia de contrato incluye:

1. Fixtures FHIR sintéticos mínimos y completos por tipo soportado.
2. Fixtures inválidos por versión, perfil, cardinalidad, referencia y terminología.
3. Tabla explícita `FHIR path -> campo interno -> transformación -> pérdida aceptada`.
4. Golden del modelo interno normalizado, no de formato incidental.
5. Prueba de identidad estable e idempotencia al reingerir el mismo recurso.
6. Prueba de actualización con `versionId` o estrategia equivalente.
7. Referencias fuera de orden, faltantes y cíclicas.
8. Zona horaria, precisión temporal, códigos desconocidos y extensiones.
9. Cuarentena con razón estable; nunca ingesta parcial silenciosa.
10. Compatibilidad explícita por versión; no prometer soporte FHIR general.

No se exige round-trip perfecto si el modelo interno descarta campos por decisión. Toda pérdida debe estar documentada y probada. Los datos de producción de una institución no pueden transformarse en fixtures sin un proceso aprobado de desidentificación.

## Idempotencia y concurrencia

Cada comando con efectos debe definir:

- alcance de la clave: actor, operación, recurso y versión;
- ventana de retención;
- respuesta para repetición terminada, en curso y fallida;
- constraint único o serialización que resista carreras;
- qué errores admiten retry;
- cómo se detecta un payload distinto con la misma clave.

Casos obligatorios: dos requests secuenciales iguales, dos concurrentes, mismo ID con payload distinto, crash después de persistir pero antes de responder, fallo de publicación después del commit y replay desde dead-letter. La expectativa es efecto de negocio único, no necesariamente una sola invocación física.

## E2E por flujo

| Flujo                 | Escenario feliz                               | Escenarios críticos                                |
| --------------------- | --------------------------------------------- | -------------------------------------------------- |
| F-01 Acceso           | usuario activo inicia y cierra sesión         | inválido, suspendido, recuperación                 |
| F-02 Administración   | admin crea/suspende practitioner              | no admin, rollback parcial, duplicado              |
| F-03 Timeline         | rol autorizado lista paciente y eventos       | admin, suspendido, otro ámbito                     |
| F-04 Ingesta FHIR     | recurso soportado crea/actualiza una vez      | inválido, referencia faltante, replay              |
| F-05 Audio/ASR        | consentimiento, captura y transcripción local | permiso negado, interrupción, cleanup              |
| F-06 NER/tokens       | detecta, tokeniza y revierte autorizado       | falso negativo, token alterado, sin permiso        |
| F-07 Síntesis         | fixture sintético usa fake/proveedor sandbox  | contenido no sintético, timeout, redacción de logs |
| F-08 Resumen/cache    | genera y reutiliza versión exacta             | fuente cambia, expiración, aislamiento RLS         |
| F-09 Eliminación      | borra original y derivados                    | retry, artefacto ausente, fallo parcial            |
| F-10 Outbox/auditoría | publica una vez de forma observable           | worker crash, duplicado, dead-letter               |

Cada E2E registra requisito, ADR, fixture, versión, resultado y evidencia. No se ejecutan pruebas destructivas contra ambientes compartidos.

## Spikes de factibilidad

Un spike responde una pregunta acotada y no entrega una feature. Debe declarar hipótesis, hardware, dataset sintético, métricas, presupuesto y criterio de abandono.

| Spike              | Pregunta                                   | Métricas mínimas                                            | Salida                  |
| ------------------ | ------------------------------------------ | ----------------------------------------------------------- | ----------------------- |
| SP-01 ASR local    | ¿Es viable en dispositivos objetivo?       | real-time factor, latencia, RAM, batería, WER/CER por ruido | recomendación y límites |
| SP-02 NER          | ¿Qué entidades se detectan de forma útil?  | precision/recall/F1 por clase y falsos negativos críticos   | taxonomía y umbral      |
| SP-03 Tokenización | ¿La reversión es determinista y segura?    | colisiones, corrupción, latencia, aislamiento de mapa       | formato versionado      |
| SP-04 FHIR         | ¿Qué perfiles y recursos se pueden mapear? | cobertura de campos, pérdidas, errores por fixture          | matriz de mapping       |
| SP-05 Síntesis     | ¿La abstracción tolera proveedores/fallos? | latencia, costo estimado, timeout, calidad con sintéticos   | contrato de provider    |
| SP-06 Cache        | ¿La clave evita obsolescencia?             | hit ratio sintético, invalidación, tamaño, latencia         | política de cache       |

Los resultados negativos son válidos. No se convierten en afirmaciones clínicas ni se extrapolan fuera del hardware y corpus evaluados.

## Gates por corte vertical

1. Requisito y ADR vinculados; amenazas y riesgos actualizados.
2. Datos exclusivamente sintéticos y fixture revisado.
3. Tests de la capa de autoridad pasan localmente.
4. Fallos, retry, idempotencia y cleanup demostrados.
5. Logs inspeccionados para ausencia de contenido sensible.
6. E2E del corte pasa y produce evidencia reproducible.
7. Limitaciones y preguntas abiertas permanecen visibles.
8. CI incorpora el test estable; benchmarks pesados pueden quedar como ejecución manual documentada.

## Comandos y evidencia actual

- Base: `pnpm db:reset`, `pnpm db:lint`, `pnpm db:test` y `pnpm db:upgrade:test` para validar upgrades con datos sintéticos previos (`package.json:12-15`).
- Flutter: `pnpm app:format:check`, `pnpm app:analyze`, `pnpm app:test` (`package.json:16-19`).
- Edge: `pnpm functions:check` (`package.json:21-26`).
- Integración local fases 3+4: `pnpm integration:local` hace reset al inicio y en `finally` al terminar, autentica actores seed, llama RPC/PostgREST y Edge local, y restablece el baseline sintético. Es destructivo exclusivamente para Supabase local desechable; nunca borrar historia/auditoría manualmente ni usar con proyecto remoto. No imprime tokens, contraseñas, correos ni cuerpos de respuesta.
- Pipeline: `pnpm pipeline:check`, que en el baseline solo validaba el scaffold (`package.json:20`).
- Documentación: `pnpm docs:format:check` y `pnpm docs:lint` (`package.json:27-29`).

La trazabilidad objetivo está en [requirements-traceability.md](appendices/requirements-traceability.md) y las brechas vigentes en [evidence-index.md](appendices/evidence-index.md).

### Evidencia dirigida fase 5.1 (2026-10-11)

`pnpm security:evidence:phase51` inspecciona el esquema local resetado, grants/runtime DML, `proconfig` de funciones `SECURITY DEFINER`, policies/helper clínicos legacy, opciones de vistas, presencia de índices y literales de claves/JWT en archivos del working tree; además imprime `EXPLAIN` estimado para organización+hospitalización, membership, role assignment y care assignment. EXPLAIN solo muestra planificación/indexabilidad sobre el seed pequeño: no prueba ejecución de RLS ni comportamiento runtime. No se exige que el planner elija un índice con el seed pequeño ni se agregan índices para alterar ese plan. No usa `ANALYZE` ni datos reales.

`care_assignment_operations_phase2.test.sql` comprueba adicionalmente que metadata de auditoría no contiene campos de email, credenciales, RUT, nombres ni contenido/payload clínico. Las pruebas existentes comprueban denegaciones atribuibles, vistas invoker/barrier, technician sin asignación/acceso clínico y filas sin vínculo inequívoco ocultas. `integration:local` verifica censo, `clinical_patient_demographics_by_hospitalization` y timeline permitidos/manipulados/revocados con el mismo JWT clínico; también prueba Edge 403/400, alta 201, replay 200, conflicto 409 y denegación del caller clínico/Service Role. La identidad sintética única se mantiene en memoria; reset antes/después limpia exclusivamente el proyecto local desechable e incluye auditoría append-only.

La evidencia es local y acotada; no constituye autorización para producción ni garantía de seguridad. La carrera concurrente del último Administrador entre dos sesiones sigue siendo un límite: pgTAP valida contrato/invariantes sin concurrencia real y no se agregó una prueba determinista de bloqueo entre dos procesos.

Registro de ejecución: 2026-10-11, rama `main`, HEAD `4e04ae7ca4e3bfa498d872d0d3fd2a1ed3be7c43`; working tree ya estaba y continúa modificado por trabajo previo sin commit. `pnpm db:reset` se ejecutó dos veces para restaurar fixtures tras la integración local; `pnpm security:evidence:phase51` pasó; `pnpm integration:local` pasó; `pnpm db:lint` pasó; `pnpm db:test` pasó con 391 tests/10 archivos; `pnpm docs:format:check`, `pnpm docs:lint` y `git diff --check` pasaron. El primer DB test se ejecutó después de integración y mostró filas/auditoría persistentes de esa ejecución; el reset aisló ambos recorridos y el DB test limpio pasó. Upgrade, gates completos de app/Edge y gate final 5.2 omitidos deliberadamente.

### Gate final fase 5.2 (2026-10-11)

Ejecución final completada en macOS 27.0.1 arm64, rama `main`, HEAD `4e04ae7ca4e3bfa498d872d0d3fd2a1ed3be7c43`; working tree preexistente modificado, sin commit. Secuencia: `pnpm db:reset`; `pnpm db:lint`; `pnpm db:test` (391/391, 10 archivos); `pnpm db:upgrade:test` (upgrade aislado baseline→fase 4.3 aprobado); `pnpm functions:check` (14/14 tests Deno); `pnpm integration:local` (Edge real aprobado); `pnpm security:evidence:phase51` (10 checks PASS, sin candidatos JWT/Service Role versionados); `pnpm app:format:check` (37 archivos, 0 cambios); `pnpm app:analyze` (sin issues); `pnpm app:test` (58 tests); `pnpm pipeline:check`; `pnpm docs:format:check`; `pnpm docs:lint` (52 archivos, 0 issues); `git diff --check` (limpio). La integración verificó alta Edge 201, replay idéntico 200, conflicto 409, exactamente un Auth user/perfil/membresía/grant, caller clínico 403 y Service Role no autorizada como actor (denegación 401/403). Utilizó identidad sintética única en memoria y reset antes/después; inspección posterior del baseline: 0 eventos de auditoría de integración, 5 Auth users seed y 9 asignaciones asistenciales seed. La primera ejecución se detuvo por puerto 54324 del harness upgrade; se corrigió `inbucket`→`mailpit` en exclusiones. Una ejecución posterior detectó claves entrecomilladas en `supabase status -o env` y el mensaje de éxito prematuro en `finally`; el parser y reporte se corrigieron y la secuencia completa final pasó. La evidencia de concurrencia del último Administrador en dos sesiones no se ejecutó; permanece abierta. Resultado local/sintético únicamente: no afirma producción, datos reales, cumplimiento regulatorio, FHIR completo, escritura clínica, emergency access ni auditoría de lectura.
Phase 4.2 adds PostgreSQL preflight/registration tests for normalized Auth-email matching, sanitised denial audit, authority revalidation and replay; runtime `profiles` write guards; Deno HTTP-handler tests for revocation cleanup and ambiguous post-commit retry; and upgrade-harness coverage. This evidence is limited to the backend and does not imply implementation of the other Flutter administration flows; role composition has separate evidence below. Auth and PostgreSQL do not share a distributed transaction: a process crash after Auth creation and before registration can leave an Auth identity orphaned, while observable registration failures invoke compensating `auth.admin.deleteUser`.

### Gate UI pre-PR: composición de permisos

La evidencia dirigida de Flutter cubre autorización por ambos permisos efectivos, rechazo y no consulta de catálogo/roles sin acceso, carga/error/reintento, roles activos no protegidos únicamente, protección ante permisos ocultos, composición completa y vacía confirmada, cambios de rol/organización sin contenido anterior, sanitización de denegaciones, retry con snapshot/clave idénticos y clave nueva para gesto nuevo, e invalidación tras éxito. Para care assignments, cubre el nombre histórico del asignado suspendido, su indicador independiente de falta de acceso, filtro local por paciente autorizado o UUID de episodio, tarjeta sin título “Ingreso” duplicado y fechas institucionales sin segundos con intervalos para revocadas/finalizadas. El gate pre-PR ejecuta una vez `pnpm app:format:check`, `pnpm app:analyze`, `pnpm app:test`, `pnpm docs:format:check`, `pnpm docs:lint` y `git diff --check`. No se ejecutan reset, tests/upgrade de DB, Edge, integración ni pipeline cuando esas capas no cambian.

### Registro de ejecución: historial asistencial y mutabilidad de roles (2026-10-12)

Rama `main`, HEAD `3d58988ea294269d525868ecfcc067bb0a1a4b50`, working tree modificado sin commit. `pnpm db:reset` aplicó `20261011380000`, `20261011390000` y `20261011400000`; `pnpm db:lint` sin errores de esquema; `pnpm db:test` 405/405 en 10 archivos, con los 14 asserts nuevos de mutabilidad de rol dentro de `iam_administration_phase4.test.sql`; `pnpm db:upgrade:test` aprobó el upgrade aislado baseline→fase 4.3, confirmando que degradar el rol seed no rompe `bootstrap_legacy_practitioner_iam`, que se ejecuta en una migración anterior. `pnpm app:analyze` sin issues y `pnpm app:test` 103/103. `pnpm app:format:check` detectó tres archivos sin formatear y se corrigieron solo con `dart format`, sin cambio semántico; luego 42 archivos, 0 cambios. `pnpm docs:format:check`, `pnpm docs:lint` (53 archivos, 0 issues) y `git diff --check` pasaron. No se ejecutaron Edge, integración local, pipeline ni `security:evidence:phase51`: las capas que cambiaron son migración, Flutter y documentación. La carrera concurrente del último Administrador entre dos sesiones sigue sin verificarse.
