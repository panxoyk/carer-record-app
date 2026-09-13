# Arquitectura

El repositorio contiene Flutter en `app/`, infraestructura Supabase en `supabase/` y un scaffold del futuro pipeline FHIR en `scripts/`. En desarrollo, `scripts/run-app.sh` carga `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY` desde `.env` y las pasa a Flutter mediante `--dart-define`.

Supabase protege las tablas con RLS. Cada practitioner puede leer únicamente su perfil; administradores activos administran practitioners mediante la Edge Function `manage-practitioners`. La Service Role Key permanece exclusivamente dentro de esa función. La URL y clave publishable son identificadores públicos necesarios para un cliente móvil; no otorgan privilegios. Los practitioners activos con rol `physician`, `nurse` o `technician` pueden listar pacientes y consultar sus fichas y eventos en modo solo lectura. Los administradores no tienen acceso clínico implícito.

Los roles son `administrator`, `physician`, `nurse` y `technician`; los estados son `active` y `suspended`. Un usuario suspendido solo puede cerrar sesión. El registro público está deshabilitado.

La recuperación de contraseña usa el deep link `io.carerrecord.app://login-callback/recover`, configurado para Android, iOS y Supabase local.
