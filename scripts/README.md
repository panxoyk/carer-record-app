# Scripts

Los comandos pnpm se ejecutan desde la raíz. Los selectores de `app:test`, `functions:test` y `fhir:sync:test` son rutas relativas a `app/`, `supabase/functions/` y `scripts/fhir-sync/`, respectivamente; también aceptan selectores de caso según su runner.

| Archivo                               | Propósito y entrada                                                                   | Uso                                                                                                  |
| ------------------------------------- | ------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `run-app.mjs`                         | Orquesta preflight, Supabase, HAPI, sync, pasarela y Flutter; entrada `pnpm app:run`. | Desarrollo local automatizado.                                                                       |
| `run-app.sh`                          | Lanzador shell heredado del flujo de app.                                             | Compatibilidad/diagnóstico; el entrypoint normal multiplataforma es `run-app.mjs`.                   |
| `serve-fhir-gateway.sh`               | Sirve la función `clinical-record` en modo gateway local.                             | Diagnóstico manual; no inicia todo el stack.                                                         |
| `check-secrets.mjs`                   | Busca patrones de secretos en archivos locales tracked y no ignorados.                | `pnpm security:check`; no sustituye revisión de credenciales.                                        |
| `test_fhir_gateway_local.py`          | Prueba de integración local de la pasarela FHIR.                                      | Diagnóstico explícito; requiere servicios.                                                           |
| `test_iam_local.py`                   | Integración HTTP de Auth, Edge Functions y RLS.                                       | `pnpm integration:iam`; hace reset antes y después. **Destructivo**: solo con base local desechable. |
| `fhir-sync/generate-sync.test.mjs`    | Pruebas unitarias de generación y aplicación de sync.                                 | `pnpm fhir:sync:test generate-sync.test.mjs`.                                                        |
| `fhir-sync/demo-fixture.test.mjs`     | Pruebas del fixture HAPI sintético.                                                   | `pnpm fhir:sync:test demo-fixture.test.mjs`.                                                         |
| `fhir-sync/generate-sync.mjs`         | Proyecta recursos HAPI a SQL local; `--apply` o `--demo-assignments`.                 | Automatizado por `app:run`; manual solo diagnóstico. Nunca usar datos reales.                        |
| `fhir-sync/generate-demo-fixture.mjs` | Genera fixture HAPI sintético.                                                        | Automatizable; prueba con `node --test scripts/fhir-sync/demo-fixture.test.mjs`.                     |

Los `.sql` locales de `fhir-sync/` se generan/usan como artefactos de trabajo; no contienen migraciones de producto. No pongas secretos, Service Role Keys ni datos clínicos en argumentos, archivos, logs o fixtures. El manifiesto de asignaciones y detalles de sync están en [fhir-sync](fhir-sync/README.md).

## Validación por capa

- Flutter: `pnpm app:format:check`, `pnpm app:analyze`, `pnpm app:test test/ruta_relativa.dart`.
- Edge Functions: `pnpm functions:format:check`, `pnpm functions:lint`, `pnpm functions:typecheck`, `pnpm functions:test ruta_relativa.ts`.
- Sync: `pnpm fhir:sync:test test_relativo.mjs`.
- SQL local: `pnpm db:lint` y `pnpm db:test`; requieren Supabase local iniciado.
- `pnpm test` ejecuta suites de app, Edge y sync; `pnpm check` incluye los gates generales. Guía canónica: [testing y validación](../docs/foundation/11-testing-validation.md).
