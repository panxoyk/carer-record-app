# Backlog operativo

Este archivo organiza tareas secuenciales de implementación. El alcance, las decisiones y los criterios de aceptación canónicos permanecen en [`foundation/`](foundation/README.md), especialmente en el [roadmap de entrega](foundation/12-delivery-roadmap.md).

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
