# Arquitectura

El monorepo contiene Flutter en `app/`, infraestructura Supabase en `supabase/` y el pipeline reproducible en `scripts/`. La app recibe solo `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY` mediante `--dart-define`.

Supabase protege las tablas con RLS. Cada practitioner puede leer únicamente su perfil; administradores activos administran practitioners mediante la Edge Function `manage-practitioners`. La Service Role Key permanece exclusivamente dentro de esa función. Pacientes y eventos clínicos no tienen permisos para usuarios autenticados hasta definir la matriz clínica.

Los roles son `administrator`, `physician`, `nurse` y `technician`; los estados son `active` y `suspended`. Un usuario suspendido solo puede cerrar sesión. El registro público está deshabilitado.

La recuperación de contraseña usa el deep link `io.carerrecord.app://login-callback/recover`, configurado para Android, iOS y Supabase local.
