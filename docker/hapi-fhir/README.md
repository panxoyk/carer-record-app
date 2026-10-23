# Servidor HAPI FHIR de demostración

Servidor FHIR R4 local con 20 pacientes ficticios y episodios inpatient abiertos e históricos. Es solo desarrollo: no tiene autenticación, guarda datos en memoria y nunca debe recibir datos clínicos reales.

## Inicio rápido

Desde la raíz del repositorio, con Docker Desktop abierto:

```bash
pnpm app:run
```

`pnpm fhir:up` levanta dos servicios:

- `hapi-fhir`: HAPI 8.12.0 fijado por digest, validado con FHIR R4 v4.0.1, publicado en `http://127.0.0.1:8080/fhir`.
- `hapi-seed`: una tarea de un solo uso que espera a que HAPI responda y carga [seed/demo-patients.json](seed/demo-patients.json).

La primera vez descarga las imágenes y HAPI tarda unos minutos en arrancar. El arranque completo sincroniza estructura, asignaciones y pasarela antes de Flutter. También puedes iniciar solo HAPI con `pnpm fhir:up`. Comprueba el resultado con:

```bash
curl "http://127.0.0.1:8080/fhir/Patient?_count=3"
```

`pnpm fhir:sync` proyecta Patient/Encounter/Location a las tablas estructurales de Supabase local; `pnpm app:run` ejecuta además las asignaciones declaradas. En una base limpia se esperan 20 pacientes/episodios: 14 abiertos (8 asignados y 6 sin asignar) y 6 cerrados históricos. No purga recursos FHIR ni reemplaza asignaciones existentes: solo crea una asignación si el par episodio/membresía aún no existe, incluidas asignaciones históricas vencidas. Los episodios cerrados con `validUntil` vencido no conceden lectura clínica por sí solos; el Administrador de demo puede verlos mediante sus permisos reservados y guardas RLS. Los UUID de Patient del fixture son constantes y válidos; los Encounter IDs se conservan para el manifest de asignaciones.

## Comandos

| Necesidad                                             | Comando                                               |
| ----------------------------------------------------- | ----------------------------------------------------- |
| Levantar el servidor y cargar los datos               | `pnpm fhir:up`                                        |
| Ver los logs                                          | `pnpm fhir:logs`                                      |
| Detener y borrar el servidor y sus datos              | `pnpm fhir:down`                                      |
| Sincronizar Patient/Encounter/Location                | `pnpm fhir:sync`                                      |
| Crear asignaciones demo desde el manifest             | `pnpm fhir:demo:assignments`                          |
| Tests unitarios del mapper y SQL local                | `pnpm fhir:sync:test`                                 |
| Usar otro puerto (por ejemplo, el 8081)               | `HAPI_FHIR_PORT=8081 pnpm fhir:up`                    |
| Sobrescribir la imagen fijada (solo versión validada) | `HAPI_FHIR_IMAGE=<imagen@sha256:digest> pnpm fhir:up` |

Los datos viven en memoria. Si el contenedor se reinicia o ejecutas `pnpm fhir:down`, se pierden; `pnpm fhir:up` vuelve a aplicar el transaction bundle con `PUT Resource/id`. Es idempotente y no elimina recursos ajenos al bundle. El sync consulta HAPI paginadamente y deriva UUID internos SHA-256 deterministas de logical source + tipo + `Resource.id` (bits RFC 4122; no usa IDs numéricos).

## Qué contiene

El bundle contiene Organization, jerarquía Location sala/cama, 20 Patient y 20 Encounter: 14 abiertos y 6 cerrados históricos con `validUntil`. Tras sync en base limpia, 8 episodios abiertos tienen asignación demo y 6 quedan sin asignar. Incluye recursos clínicos sintéticos relacionados; los IDs Patient son UUID fijos y los Encounter IDs se mantienen para assignments. MedicationRequest expresa órdenes ficticias, no administraciones.

| Episodio            | Escenario sintético                                                                                      |
| ------------------- | -------------------------------------------------------------------------------------------------------- |
| `enc-med-ana`       | Medicina: observaciones seriadas, paneles de laboratorio vinculados, condiciones y orden de medicamento. |
| `enc-surg-matias`   | Cirugía: procedimiento completado, órdenes y resultados/observaciones seriados.                          |
| `enc-shared`        | Traslado entre dos camas con observaciones seriadas y paneles de laboratorio.                            |
| `enc-closed-ana`    | Egreso tras observación breve; evidencia acotada al episodio.                                            |
| `enc-closed-matias` | Egreso tras procedimiento menor sintético; evidencia anterior al egreso.                                 |

El bundle se puede regenerar determinísticamente con `node scripts/fhir-sync/generate-demo-fixture.mjs` y validar con `node --test scripts/fhir-sync/demo-fixture.test.mjs`. Los recursos usan referencias transaccionales `PUT Resource/id` y un `fullUrl` absoluto coherente. Todo el contenido es inventado, exclusivamente demostrativo, no representa indicaciones ni una evaluación de calidad clínica y nunca debe emplearse para decisiones asistenciales.

## Cómo se conecta con la app

- La función Edge `clinical-record` consulta HAPI desde el servidor con `FHIR_SERVER_BASE_URL=http://hapi-fhir:8080/fhir`. Esta configuración pertenece al env-file de la función, no a `.env` ni Flutter: se usa `docker/hapi-fhir/gateway.env.local` si existe, con `gateway.env.example` como fallback. `pnpm fhir:gateway:serve` (o `pnpm app:run`) conecta `carer-record-hapi-fhir` a `supabase_network_carer-record` con el alias `hapi-fhir`. La red y alias deben estar conectados también al reutilizar una pasarela ya activa.
- La publicación de HAPI permanece ligada a `127.0.0.1:8080` para herramientas del host. El contenedor del dispositivo no obtiene ruta al alias `hapi-fhir` ni evita la autorización Edge/RPC; la función solo consulta tras validar sesión y autorización RLS. La configuración móvil directa ADR-019 ya no es el camino de la ficha protegida.
- `pnpm fhir:sync` genera y aplica SQL local como propietario Docker; `pnpm fhir:demo:assignments` es un paso separado y explícito basado en `scripts/fhir-sync/demo-assignments.json`. No infiere profesionales desde autoría FHIR y no reactiva vínculos revocados.

## Problemas frecuentes

- **El puerto 8080 está ocupado.** Detén el otro servidor (por ejemplo, un HAPI que corra en WSL o en otro contenedor) o usa `HAPI_FHIR_PORT`.
- **`pnpm fhir:sync` dice que no encuentra `supabase_db_*`.** Levanta Supabase con `pnpm db:start`.
- **La función no conecta con HAPI.** Comprueba que `pnpm db:start` y `pnpm fhir:up` estén activos y vuelve a ejecutar `pnpm fhir:gateway:serve`; no cambies el puerto publicado a una interfaz accesible por la red.
- **La carga de datos falló.** `pnpm fhir:logs` muestra la respuesta de HAPI. Tras corregir el problema, ejecuta `pnpm fhir:down` y `pnpm fhir:up`.

## Límites

- La imagen predeterminada está fijada a HAPI 8.12.0 por digest y fue validada con FHIR R4 v4.0.1.
- El servidor no autentica: cualquiera que alcance el puerto puede leer los datos. En el diseño objetivo, la autorización la decide RLS en Supabase.
- El puerto se publica solo en `127.0.0.1` por compatibilidad con herramientas locales. El acceso servidor usa una red Docker privada entre runtime Edge y HAPI; esto es configuración de desarrollo local, no un despliegue productivo.
- Las asignaciones fixture autorizan lectura de demo; no representan inferencias clínicas ni se crean con el sync estructural.
- Los fixtures SQL legacy se conservan para las pruebas existentes; la lista de demostración usa `fhir_clinical_census_by_hospitalization` y solo muestra episodios FHIR enlazados y autorizados.
