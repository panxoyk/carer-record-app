# Guía de desarrollo

Este documento registra decisiones de arquitectura y acuerdos de trabajo estables. Debe leerse antes de proponer cambios relevantes.

## Límites actuales del producto

Esta etapa cubre acceso por email/contraseña, recuperación de contraseña, administración de usuarios y consulta clínica de solo lectura. Los roles válidos son `administrator`, `physician`, `nurse` y `technician`; una cuenta puede estar `active` o `suspended`.

No se debe añadir acceso clínico implícito. La matriz vigente está en `docs/roadmap.md`: los roles asistenciales activos pueden leer pacientes y eventos, mientras administradores y cuentas suspendidas no tienen acceso clínico. No se permite escritura clínica hasta definir y documentar una matriz explícita para esas operaciones.

## Decisiones de arquitectura

- Flutter es la aplicación móvil; Riverpod gestiona estado, GoRouter protege navegación y Supabase provee Auth, Postgres y Edge Functions.
- La autorización se impone en Supabase con RLS. Un guard de interfaz mejora la experiencia, pero nunca reemplaza una política o validación de servidor.
- Las operaciones administrativas que requieren privilegios se realizan mediante Edge Functions. La Service Role Key se lee únicamente con `Deno.env` en el servidor; nunca en Flutter ni en archivos versionados.
- Supabase se mantiene como infraestructura versionada. No se editan migraciones ya aplicadas: cada evolución se expresa en una migración aditiva.
- La app usa URL y clave publishable de Supabase desde `.env` durante desarrollo, pasadas con `--dart-define`. Son identificadores públicos de cliente, no credenciales privilegiadas. `.env` nunca se versiona.
- Cualquier JSONB debe tener un modelo Dart tipado y una restricción SQL que limite su forma a objeto.

## Forma de implementar

- Organizar cada dominio en `data`, `domain` y `presentation`. El acceso remoto queda detrás de repositorios; los providers pertenecen a presentación.
- Hacer primero la autorización y sus validaciones de base de datos, después el modelo/repositorio y finalmente la interfaz.
- Favorecer cambios pequeños y verticales. Para una funcionalidad clínica: matriz de permisos → migración/RLS → tests de autorización → repositorio/modelo → ruta/pantalla.
- No introducir secretos, credenciales reales ni datos clínicos reales en el repositorio. Los usuarios de `supabase/seed.sql` son exclusivamente datos de desarrollo local.
- Trabajar directamente sobre `main` con commits pequeños e independientes. Cada commit debe representar un cambio lógico completo e incluir sus pruebas y documentación cuando correspondan.
- Mantener actualizados `docs/roadmap.md` y `docs/todo.md` cuando cambie el alcance de una entrega. Actualizar `docs/architecture.md` cuando cambien límites o decisiones técnicas.

## Calidad requerida

No se ejecuta la suite completa después de cada edición. Durante la implementación se usan validaciones dirigidas cuando aportan feedback y, antes de entregar, se ejecutan una vez las verificaciones correspondientes a las capas modificadas:

- Documentación: `git diff --check` y revisión de enlaces y consistencia.
- Flutter: `pnpm app:format:check`, `pnpm app:analyze` y las pruebas Dart relacionadas cuando cambie comportamiento.
- Pipeline: `pnpm pipeline:check` y sus pruebas relacionadas.
- Edge Functions: formato, lint, comprobación de tipos y pruebas Deno relacionadas.
- Base de datos, migraciones o RLS: `pnpm db:reset`, `pnpm db:lint` y `pnpm db:test`.

La suite completa se reserva para cambios transversales o cuando se solicite explícitamente. `db:reset` no se ejecuta para cambios que no afecten la base de datos. Si una verificación no puede ejecutarse, debe indicarse al entregar.

Para iniciar la app local: copiar `.env.example` a `.env`, levantar `pnpm db:start`, completar los valores mostrados por Supabase y ejecutar `pnpm app:run`.
