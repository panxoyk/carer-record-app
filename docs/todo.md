# Backlog operativo

Este archivo es una lluvia de ideas operativa por revisar, no una secuencia comprometida. El alcance, las decisiones, estados y criterios canónicos permanecen en [`foundation/`](foundation/README.md), especialmente en el [roadmap de entrega](foundation/12-delivery-roadmap.md). Las tareas históricas cerradas se conservan como historial, no como promesas vigentes.

## Corte FHIR autorizado (2026-10-23)

- [x] Fixture reproducible de cinco pacientes; los diez pacientes HAPI legacy se conservaron. Sincronización estructural idempotente produce 15 episodios locales; los usuarios clínicos ven tres asignados cada uno.
- [x] Pasarela `clinical-record` y DTOs tipados; censo filtrado por RLS, autorización `record`/`timeline`, retiro del bypass de consulta directa desde Flutter. No equivale a ingesta FHIR completa.
- [x] Integración HTTP para Ana y Matías (tres episodios por cuenta), foreign 404, anónimo 404/401 según frontera, service-role 401 y rechazo de insert cerrado.
- [x] Gate final ejecutado por sesión principal; evidencia, comandos y límites en [gate FHIR autorizado](foundation/11-testing-validation.md#gate-fhir-autorizado-2026-10-23) y [EV-INT-005](foundation/appendices/evidence-index.md#integración-fhir-autorizada-2026-10-23).
- [ ] GUI/hardware/manual: recorrido físico no ejecutado en este corte.
- [ ] Cerrar exposición del HAPI legado: el runtime aún escucha en `0.0.0.0`; compose loopback no cierra RK-031.

El detalle contractual y de evidencia está en [ADR-020](foundation/decisions/adr-020-fhir-server-structural-sync.md) y [testing y validación](foundation/11-testing-validation.md); los ítems FHIR anteriores que describen lectura directa, fixture de diez o validación manual son históricos/obsoletos frente a ADR-020.

## Gate de cierre fase 5.2

- [x] Ejecutar secuencia final documentada en `foundation/11-testing-validation.md` sobre baseline local sintético limpio.
- [x] Hacer autocontenido `integration:local` con reset local previo/finally; no borrar manualmente auditoría append-only.
- [x] Añadir escenarios HTTP Edge alta/replay/conflicto, caller clínico y rechazo de Service Role como actor.
- [x] Mantener como límite la concurrencia de dos sesiones del último Administrador; no afirmar evidencia que no se ejecutó.
- [x] Registrar resultados y límites en el índice de evidencia y cerrar solo lo respaldado por la ejecución.

## Cierre de brechas MVP

- [x] Cerrar la vista Flutter de composición de permisos: `/roles`, roles activos no protegidos existentes, acceso por `iam.role.read` + `iam.role.manage`, reemplazo completo confirmado y gate UI pre-PR documentado. No incluye CRUD de roles ni cambios a roles protegidos.

### 1. Textos clínicos y fechas

- [x] Sustituir textos que afirman estados clínicos no respaldados por los datos disponibles.
- [x] Definir la zona horaria institucional IANA de la demo.
- [x] Formatear fechas y horas según esa zona horaria.
- [x] Evitar rótulos temporales relativos ambiguos cuando se presente información clínica.
- [x] Añadir pruebas dirigidas para fechas, zona horaria y textos relevantes.

### 2. Estados de las vistas clínicas

- [x] Definir estados consistentes de carga, vacío, no encontrado y error.
- [x] Añadir una acción de reintento segura para listado, detalle y timeline.
- [x] Evitar presentar datos parciales como vigentes después de un error.
- [ ] Validar manualmente los estados de consulta sin resultados, error de red y sesión expirada.

### 3. Recuperación y roles

- [ ] Validar recuperación de contraseña con la aplicación abierta.
- [ ] Validar recuperación de contraseña con la aplicación cerrada.
- [ ] Verificar los recorridos de UI para roles clínicos, administrador y cuenta suspendida.
- [ ] Registrar evidencia manual reproducible de los recorridos validados.
- [ ] Exponer en Flutter la gestión de roles que el servidor ya soporta. Hoy `create_iam_role`, `update_iam_role` y `deactivate_iam_role` existen como RPC públicas auditadas, y `deactivate_iam_role` ya está probada en pgTAP desde la degradación del rol seed, pero ninguna tiene pantalla: la composición de `/roles` no las invoca. `activate_iam_role` no existe, de modo que un rol desactivado queda inerte sin una migración. Nota: los roles del seed son de prueba y el hospital los reemplaza durante el onboarding, así que la reactivación no es urgente, pero sin ella el deactivate es irreversible desde la app.
- [ ] Evaluar el borrado duro de roles. Hoy solo existe desactivación (soft delete, `status = 'inactive'`) porque todas las FK a `roles` son `on delete restrict` y la auditoría es append-only.

### 4. Pruebas y guardrails

- [ ] Añadir pruebas Flutter dirigidas a fechas, estados de vista y reintentos.
- [ ] Ejecutar las validaciones de Flutter y base de datos afectadas por cada corte.
- [ ] Incorporar un secret scan en CI.
- [ ] Actualizar la evidencia de foundation al cerrar cada bloque.

## Corte ASR local y síntesis local (2026-10-12)

- [x] ADR-016 y ADR-017 aceptadas, con ADR-015 en parte sustituida y ADR-008/ADR-009 sustituidas.
- [x] Migración aditiva: `transcription_metadata` validado, audio almacenado retirado por completo y timeline proyectando el texto confirmado.
- [x] pgTAP del contrato corregido, incluida la prueba de privacidad que falla si reaparece un bucket, una política o una columna de audio.
- [x] Motor `sherpa_onnx` detrás de `AsrEngine`, con manifiesto versionado y fallo cerrado sin modelo.
- [x] Flujo grabar → transcribir → revisar → confirmar → purgar, sin reproducción de audio en la bitácora.
- [x] `SynthesisProvider` local con adaptador GGUF y fake determinista; la asistencia nunca bloquea la publicación.
- [x] Retiro de `clinical-summary` y de la Edge Function de síntesis.
- [ ] Cerrar el spike SP-01 con medición en un dispositivo arm64 real: latencia, factor de tiempo real, RAM, batería, temperatura y tamaño de descarga.
- [ ] Registrar el corpus sintético del benchmark de síntesis y sus resultados; no afirmar calidad clínica.
- [x] Descarga de pesos en el dispositivo con el flujo de primer arranque: pantalla «Preparar el dispositivo», progreso, verificación por `sha256` y salida sin modelos que no bloquea la bitácora. Sustituye la instalación manual por `adb push`.
- [ ] Medir en un arm64 real el coste de la descompresión bzip2 en streaming y el pico de RAM durante la instalación de los 198 MB de ASR.
- [ ] Medir y decidir el plazo de expiración de capturas pendientes (`Q-PRIV-03`) con el vault ya implementado.
- [ ] Cerrar el arranque sin credenciales de Supabase. Hoy `initializeSupabase` lanza en `main()` y la app no llega a pintar, así que un clon sin `.env` no puede ni descargar los modelos; la pantalla de preparación no depende del backend.

## Estado de arquitectura y reconciliación de notas

- [x] Aplicar ADR-018: `on_device_ai` posee ASR, síntesis, UI/gestión de modelos y lifecycle de capacidades; `context_note` conserva sus tres controladores, puertos de feature, vault y casos de uso. `LocalCapabilityRepository` es la única frontera de provisioning y los leases son genéricos.
- [x] Añadir `20261012020000_context_note_publication_reconciliation.sql` y prueba pgTAP: RPC read-only que reautoriza y solo devuelve true para payload confirmado exactamente coincidente del propio autor; no amplía grants de escritura.
- [x] Mantener pruebas de cleanup básico: registro previo a captura, purga idempotente y retry si falla el borrado real del archivo. Esto no acredita recuperación general tras crash.
- [ ] Habilitar/ejecutar decodificación nativa ASR real con manifiesto y asset sintético declarado; el test de integración está env-gated. Resolver incompatibilidad runtime/modelo y completar SP-01 en hardware arm64 real.
- [ ] Implementar UI de señalización NER; el caso de uso local existe, pero no hay interfaz de entidades ni evaluación sintética de falsos negativos.
- [ ] Registrar benchmark sintético de síntesis local. Los tests con fake no prueban equivalencia funcional ni rendimiento del adaptador nativo.
- [ ] Implementar restauración offline/outbox, backoff y recuperación ante crash; siguen siendo requisitos, no funcionalidades cerradas.
- [ ] Resolver Q-PRIV-03 con decisión de producto sobre TTL y validar política; las 24 horas actuales en código son default técnico, no decisión aprobada.
- [x] Ejecutar el gate final proporcional tras los últimos cambios y registrar comandos/resultados sin reutilizar los conteos previos como gate final ([evidencia](foundation/11-testing-validation.md#gate-final-del-módulo-ia-local-compartido-2026-10-18)).

## Historial sustituido: integración HAPI FHIR directa (2026-10-21)

Histórico obsoleto: la dirección de lectura directa descrita abajo fue sustituida por ADR-020; no tomar estas casillas cerradas como estado vigente ni las pendientes como secuencia comprometida.

- [x] Lista de pacientes desde HAPI FHIR R4, paginada y con búsqueda por nombre o identificador, en `app/lib/domains/fhir_record/` (cliente HTTP, mapper hacia entidades internas y pantallas). Validada manualmente en un dispositivo Android.
- [x] Ficha clínica completa por `Patient/{id}/$everything` con paginación; es la pantalla `/fhir/patients/:patientId`, sin enlace visible desde el listado.
- [x] Enlace con la bitácora: `scripts/fhir-sync/generate-sync.mjs` sincroniza paciente, hospitalización, ubicación y asignación asistencial en Supabase local con ids derivados del id de FHIR (`pnpm fhir:sync`). Probado con 633 pacientes.
- [x] Servidor HAPI FHIR de demostración en `docker/hapi-fhir` con 10 pacientes sintéticos y carga automática.
- [ ] Validar `pnpm fhir:up` y `pnpm fhir:sync` en un equipo limpio (el compose se probó con un servidor simulado, no con Docker real) y fijar `HAPI_FHIR_TAG` en una versión validada.
- [x] ADR-019 (lectura directa de FHIR y bitácora enlazada) aceptada; ADR-004 queda en parte sustituida. Actualizados el README y el índice de foundation, el índice de ADR, la integración FHIR, los flujos de ingesta y consulta clínica, el registro de riesgos, las preguntas abiertas, la trazabilidad y el índice de evidencia.
- [x] Actualizados también los documentos de foundation que reflejan ADR-019: alcance, arquitectura objetivo, control de acceso, pruebas y validación, y roadmap.
- [ ] Añadir pruebas Flutter del módulo `fhir_record` (mapper, cliente con respuestas simuladas, paginación del listado, navegación a la bitácora) y una prueba del script de sincronización.
- [ ] Pedir la ficha por tipo de recurso y en paralelo. Con `$everything`, un paciente de 646 recursos tardó unos 90 s contra el HAPI local.
- [ ] Entregar la ficha al modelo local sección por sección (ADR-017 y ADR-018).
- [ ] Proteger el acceso a HAPI (por ejemplo, un proxy que valide el JWT de Supabase). Hoy el servidor no autentica y la restricción por rol es solo de interfaz.
- [x] `FHIR_BASE_URL` en `.env` y `.env.example`, que `scripts/run-app.sh` pasa a Flutter cuando no está vacío.
- [ ] Validar manualmente el recorrido lista → bitácora → información del paciente → volver, y decidir si el `push` en `patient_screens.dart` pasa a ser la regla.
- [ ] Propagar a Supabase cambios posteriores del HAPI (altas, cambios de sala o cama); hoy solo se copia la primera vez.
