# ADR-003: Supabase como backend versionado

- Estado: Aceptada
- Fecha: 2026-09-27
- Alcance: autenticación, Postgres, RLS, almacenamiento futuro y Edge Functions

## Contexto

El prototipo necesita autenticación, persistencia relacional, autorización por fila y funciones servidor sin construir una plataforma completa. Flutter debe usar una API soportada y no conectar directamente con credenciales privilegiadas.

## Decisión

Usar Supabase para Auth, Postgres/PostgREST, RLS y Edge Functions. Toda evolución de esquema se expresa como migración aditiva. Flutter usa URL y clave publishable; RLS decide acceso. Las operaciones que necesitan Service Role se encapsulan en Edge Functions que autentican y autorizan al caller antes de elevar privilegios.

Supabase es un componente sustituible a nivel de dominio: repositorios Flutter y fronteras de servicio evitan propagar detalles de PostgREST o SDK a entidades. Esta ADR no decide proveedor cloud, región, tier, backups ni configuración productiva.

## Alternativas consideradas

- Backend propio: más control, pero mayor superficie operacional y menor velocidad académica.
- Firebase: buen soporte móvil, pero el modelo relacional y RLS/Postgres se ajustan mejor a los contratos actuales.
- Base local sin backend: insuficiente para probar autorización multiusuario y funciones privilegiadas.

## Consecuencias

- Las políticas SQL se convierten en control crítico y reciben tests pgTAP.
- La clave publishable puede estar en cliente; Service Role no.
- Las migraciones y tipos generados deben mantenerse sincronizados.
- Existe dependencia operacional y semántica de Supabase que los repositorios solo reducen, no eliminan.
- Un guard Flutter mejora experiencia, pero no otorga ni revoca autoridad.

## Riesgos

- Una tabla, bucket, vista o RPC nueva puede quedar expuesta por grants/RLS incorrectos.
- `security definer` y Service Role amplían el impacto de errores.
- Drift entre local y remoto puede invalidar evidencia.
- Lock-in en Auth, SDK y Edge runtime.

## Evidencia

- `app/pubspec.yaml:10-15` declara `supabase_flutter`.
- `supabase/config.toml:3-43` configura API, Postgres, Auth y Edge Functions locales.
- `app/lib/core/network/supabase_client.dart:4-19` inicializa un único cliente publishable.
- `supabase/migrations/20260912000000_harden_function_privileges.sql:1-56` endurece helpers RLS.
- `supabase/functions/create-practitioner/index.ts:26-45` autoriza al caller antes del cliente privilegiado.

La configuración observada es local; no prueba hardening, residencia o resiliencia productiva.
