# Handoff de desarrollo

## Estado actual

La primera entrega de plataforma está implementada y validada localmente: autenticación por email/contraseña, recuperación, roles (`administrator`, `physician`, `nurse`, `technician`), suspensión de cuentas y gestión administrativa de practitioners. Flutter usa Riverpod, GoRouter y Supabase; la infraestructura vive en `supabase/` y se reconstruye con `pnpm db:reset`.

No hay funcionalidad clínica aún. Pacientes y eventos clínicos no tienen políticas RLS para usuarios autenticados, ni rutas o pantallas Flutter. Esta restricción es intencional.

## Convenciones

- No modificar migraciones ya existentes: crear siempre una migración nueva.
- Mantener RLS como fuente de autorización; la UI nunca sustituye controles de servidor.
- La Service Role Key solo puede usarse dentro de Edge Functions mediante `Deno.env`.
- Para desarrollo, copiar `.env.example` a `.env`; nunca versionar `.env`. La URL y clave publishable llegan a Flutter mediante `scripts/run-app.sh` y `--dart-define`.
- JSONB necesita modelo Dart tipado y una restricción SQL que asegure que es objeto.
- Mantener capas por dominio: `data`, `domain`, `presentation`; providers en presentación y acceso a Supabase detrás de repositorios.
- Formatear con `pnpm app:format`; CI exige `pnpm app:format:check`.

## Verificación mínima

```sh
pnpm app:format:check
pnpm app:analyze
pnpm app:test
pnpm pipeline:check
pnpm db:reset
pnpm exec supabase db lint --local
```

## Próxima entrega recomendada

Antes de crear vistas clínicas, definir una matriz de permisos por rol para pacientes y eventos. Después implementar, en este orden: políticas RLS y tests de autorización, listado de pacientes de solo lectura, ficha de paciente y finalmente eventos clínicos. Actualizar `docs/roadmap.md` y el Issue asociado con cada cambio funcional.

## Pendientes de plataforma

- Conectar/publicar el remoto GitHub y comprobar CI remoto.
- Añadir tests de repositorios, providers, guards, RLS y Edge Function.
- Probar recuperación de contraseña y deep links en dispositivos reales.
- Decidir si los usuarios/contraseñas locales de `supabase/seed.sql` deben sustituirse por un bootstrap no versionado.
- Crear proyecto Supabase cloud solo cuando exista un entorno objetivo.
