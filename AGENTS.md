# Instrucciones para agentes

## Antes de trabajar

- Antes de modificar código, lee [docs/development-guide.md](docs/development-guide.md).
- Para bugs, funcionalidades o deuda, consulta [docs/todo.md](docs/todo.md). Si cambia comportamiento, sigue [docs/testing-strategy.md](docs/testing-strategy.md).
- Consulta [docs/roadmap.md](docs/roadmap.md) para alcance y permisos, y [docs/architecture.md](docs/architecture.md) para cambios entre Flutter, Supabase, Edge Functions o el pipeline.
- La documentación orienta; verifica el comportamiento en el código, migraciones y pruebas afectadas.

## Implementación

- Haz el cambio correcto más pequeño y mantenlo vertical por dominio. Conserva la separación `data/domain/presentation`; el acceso remoto va detrás de repositorios.
- RLS es la autoridad de autorización. Un guard de UI no la reemplaza. No añadas acceso clínico que no figure en la matriz de permisos.
- La Service Role Key solo puede existir en servidor. No versiones secretos, credenciales ni datos clínicos reales.
- No edites migraciones aplicadas; crea migraciones aditivas.
- Respeta cambios existentes y evita modificar comportamiento no relacionado.

## Validación y cierre

- No ejecutes la suite completa después de cada edición. Usa validaciones dirigidas cuando aporten feedback.
- Antes de entregar, ejecuta una vez las verificaciones de las capas modificadas según la guía. Reserva la suite completa para cambios transversales o solicitudes explícitas. Ejecuta `db:reset` solo para cambios de base de datos.
- Informa las validaciones ejecutadas, omitidas o bloqueadas.
- Actualiza TODO, roadmap o arquitectura solo si cambian pendientes, alcance o decisiones. Marca tareas completas después de verificarlas.
- Se trabaja sobre `main`. No crees commits salvo solicitud explícita; cada commit solicitado debe contener un cambio lógico independiente.
