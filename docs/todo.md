# Backlog operativo

Este archivo organiza tareas secuenciales de implementación. El alcance, las decisiones y los criterios de aceptación canónicos permanecen en [`foundation/`](foundation/README.md), especialmente en el [roadmap de entrega](foundation/12-delivery-roadmap.md).

## Cierre de brechas MVP

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
