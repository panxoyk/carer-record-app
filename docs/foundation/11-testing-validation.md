# Estrategia de testing y validación

## Objetivo

La validación debe producir evidencia proporcionada al riesgo del prototipo, especialmente en autorización, privacidad, transformación clínica e idempotencia. No demuestra seguridad o eficacia clínica productiva. Una prueba automatizada confirma un contrato bajo condiciones conocidas; no reemplaza revisión jurídica, clínica, de usabilidad o seguridad independiente.

La suite capturada en el baseline protege RLS, privilegios SQL y enmascaramiento de RUT. El workflow observado levanta Supabase, reconstruye la base, ejecuta lint y pgTAP y luego valida Flutter (`.github/workflows/verify.yml:19-35`). La fotografía no contiene implementación ni evidencia para audio, FHIR, ASR, NER, síntesis, caché, outbox o E2E.

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

### Matriz mínima por recurso sensible

- anónimo: no puede leer ni mutar;
- sesión válida sin perfil: no obtiene autoridad clínica;
- practitioner activo con permiso: solo ejecuta la operación concedida;
- practitioner activo sin permiso: denegado aunque conozca el ID;
- cuenta suspendida: denegada inmediatamente;
- administrador: no hereda acceso clínico;
- Service Role: se usa solo en test servidor explícito, nunca como sustituto de casos RLS;
- pertenencia: un sujeto autorizado para A no observa B cuando exista segmentación;
- mutación: `insert`, `update` y `delete` se prueban por separado;
- funciones: `public` y `anon` no ejecutan helpers internos o privilegiados.

Los tests actuales proporcionan ejemplos: casos anónimo y sin perfil (`supabase/tests/patients_rls.test.sql:29-54`), roles clínicos y administrador sin acceso implícito (`supabase/tests/patients_rls.test.sql:56-116`), suspendido y denegación de mutaciones (`supabase/tests/patients_rls.test.sql:118-169`), y privilegios de funciones (`supabase/tests/function_privileges.test.sql:7-44`).

### Permisos configurables

Al implementar ADR-005, pgTAP debe probar concesión, revocación, vigencia temporal si existe, conflicto entre grants, suspensión y ausencia de fila. Debe demostrar que cambiar configuración modifica la decisión sin editar SQL y que una revocación invalida acceso en una sesión ya iniciada según el contrato definido.

### Caché y outbox

Probar restricciones únicas para claves de idempotencia, aislamiento por paciente, transición válida de estados, reclamación concurrente por un solo worker, reintento con backoff, dead-letter y ausencia de payload clínico no autorizado. Para caché, probar hit exacto, miss por versión/modelo, invalidación por cambio de fuente, expiración y RLS.

## Flutter

### Pruebas unitarias

Cubrir reglas públicas y estables: clasificación de estado, tokenización/reversión, generación de claves, invalidación de caché y presentación que evita exposición. El ejemplo vigente valida que un RUT válido revela solo tres dígitos y que uno malformado no se expone (`app/test/domains/patient/domain/entities/patient_test.dart:5-28`). Ese test protege presentación; no autoriza cargar el RUT ni anonimiza el registro.

Nombrar cada test por su resultado observable y condición, mantener una regla por test y usar fixtures locales válidos que sobrescriban solo el dato relevante. Evitar mocks, setup y helpers compartidos cuando un fixture local resulte más claro.

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

El baseline solo exigía formato, lint y typecheck (`package.json:21-26`), y `clinical-summary` devolvía intencionalmente 501 (`supabase/functions/clinical-summary/index.ts:3-19`). Antes de considerar implementada una función nueva se requieren tests HTTP para:

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

- Base: `pnpm db:reset`, `pnpm db:lint`, `pnpm db:test` (`package.json:12-14`).
- Flutter: `pnpm app:format:check`, `pnpm app:analyze`, `pnpm app:test` (`package.json:16-19`).
- Edge: `pnpm functions:check` (`package.json:21-26`).
- Pipeline: `pnpm pipeline:check`, que en el baseline solo validaba el scaffold (`package.json:20`).
- Documentación: `pnpm docs:format:check` y `pnpm docs:lint` (`package.json:27-29`).

La trazabilidad objetivo está en [requirements-traceability.md](appendices/requirements-traceability.md) y las brechas vigentes en [evidence-index.md](appendices/evidence-index.md).
