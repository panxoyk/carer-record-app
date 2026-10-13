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
- [ ] Instalar los pesos en el dispositivo mediante el flujo de descarga con progreso antes de cualquier demostración.
- [ ] Medir y decidir el plazo de expiración de capturas pendientes (`Q-PRIV-03`) con el vault ya implementado.
