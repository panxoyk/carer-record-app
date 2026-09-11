# Guía de desarrollo

Este documento registra decisiones de arquitectura y acuerdos de trabajo estables. Debe leerse antes de proponer cambios relevantes.

## Límites actuales del producto

Esta etapa cubre acceso por email/contraseña, recuperación de contraseña y administración de usuarios. Los roles válidos son `administrator`, `physician`, `nurse` y `technician`; una cuenta puede estar `active` o `suspended`.

No se debe añadir acceso clínico implícito. Pacientes y eventos clínicos permanecen sin permisos RLS, rutas ni pantallas hasta que exista una matriz de permisos explícita por rol.

## Decisiones de arquitectura

- Flutter es la aplicación móvil; Riverpod gestiona estado, GoRouter protege navegación y Supabase provee Auth, Postgres y Edge Functions.
- La autorización se impone en Supabase con RLS. Un guard de interfaz mejora la experiencia, pero nunca reemplaza una política o validación de servidor.
- Las operaciones administrativas que requieren privilegios se realizan mediante Edge Functions. La Service Role Key se lee únicamente con `Deno.env` en el servidor; nunca en Flutter ni en archivos versionados.
- Supabase se mantiene como infraestructura versionada. No se editan migraciones ya aplicadas: cada evolución se expresa en una migración aditiva.
- La app usa URL y clave publishable de Supabase desde `.env` durante desarrollo, pasadas con `--dart-define`. Son identificadores públicos de cliente, no credenciales privilegiadas. `.env` nunca se versiona.
- Cualquier JSONB debe tener un modelo Dart tipado y una restricción SQL que limite su forma a objeto.

## Forma de implementar

- Organizar cada dominio en `data`, `domain` y `presentation`. El acceso remoto queda detrás de repositorios; los providers pertenecen a presentación.
- Hacer primero la autorización y las pruebas, después el modelo/repositorio y finalmente la interfaz.
- Favorecer cambios pequeños y verticales. Para una funcionalidad clínica: matriz de permisos → migración/RLS → tests de autorización → repositorio/modelo → ruta/pantalla.
- No introducir secretos, credenciales reales ni datos clínicos reales en el repositorio. Los usuarios de `supabase/seed.sql` son exclusivamente datos de desarrollo local.
- Mantener actualizado `docs/roadmap.md` y el GitHub Issue vinculado cuando cambie el alcance de una entrega.

## Calidad requerida

Antes de entregar cambios relevantes, ejecutar:

```sh
pnpm app:format:check
pnpm app:analyze
pnpm app:test
pnpm pipeline:check
pnpm db:reset
pnpm exec supabase db lint --local
```

Para iniciar la app local: copiar `.env.example` a `.env`, levantar `pnpm db:start`, completar los valores mostrados por Supabase y ejecutar `pnpm app:run`.
