# Backlog operativo

Este archivo organiza tareas secuenciales de implementación. El alcance, las decisiones y los criterios de aceptación canónicos permanecen en [`foundation/`](foundation/README.md), especialmente en el [roadmap de entrega](foundation/12-delivery-roadmap.md).

## Gate de cierre fase 5.2

- [x] Ejecutar secuencia final documentada en `foundation/11-testing-validation.md` sobre baseline local sintético limpio.
- [x] Hacer autocontenido `integration:local` con reset local previo/finally; no borrar manualmente auditoría append-only.
- [x] Añadir escenarios HTTP Edge alta/replay/conflicto, caller clínico y rechazo de Service Role como actor.
- [x] Mantener como límite la concurrencia de dos sesiones del último Administrador; no afirmar evidencia que no se ejecutó.
- [x] Registrar resultados y límites en el índice de evidencia y cerrar solo lo respaldado por la ejecución.

## Cierre de brechas MVP

- [x] Cerrar la vista Flutter de composición de permisos: `/roles`, roles ordinarios existentes, acceso por `iam.role.read` + `iam.role.manage`, reemplazo completo confirmado y gate UI pre-PR documentado. No incluye CRUD ni roles protegidos.

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

### 4. Pruebas y guardrails

- [ ] Añadir pruebas Flutter dirigidas a fechas, estados de vista y reintentos.
- [ ] Ejecutar las validaciones de Flutter y base de datos afectadas por cada corte.
- [ ] Incorporar un secret scan en CI.
- [ ] Actualizar la evidencia de foundation al cerrar cada bloque.
