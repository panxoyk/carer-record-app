# Servidor HAPI FHIR de demostración

Servidor FHIR R4 local con cinco pacientes ficticios y cinco episodios inpatient (tres abiertos y dos cerrados). Es solo desarrollo: no tiene autenticación, guarda datos en memoria y nunca debe recibir datos clínicos reales.

## Inicio rápido

Desde la raíz del repositorio, con Docker Desktop abierto:

```bash
pnpm fhir:up
pnpm fhir:logs
```

`pnpm fhir:up` levanta dos servicios:

- `hapi-fhir`: HAPI 8.12.0 fijado por digest, validado con FHIR R4 v4.0.1, publicado en `http://127.0.0.1:8080/fhir`.
- `hapi-seed`: una tarea de un solo uso que espera a que HAPI responda y carga [seed/demo-patients.json](seed/demo-patients.json).

La primera vez descarga las imágenes y HAPI tarda unos minutos en arrancar. En `pnpm fhir:logs` espera a ver «Pacientes de demostración cargados» (o «ya estaban cargados») y sal con `Ctrl+C`. Comprueba el resultado con:

```bash
curl "http://127.0.0.1:8080/fhir/Patient?_count=3"
```

Después, `pnpm fhir:sync` proyecta Patient/Encounter/Location a las tablas estructurales de Supabase local. Tras un `pnpm db:reset`, vuelve a ejecutar sync y, si quieres las asignaciones de demostración, `pnpm fhir:demo:assignments` explícitamente.

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

Los datos viven en memoria. Si el contenedor se reinicia o ejecutas `pnpm fhir:down`, se pierden; `pnpm fhir:up` carga de nuevo el transaction bundle con `PUT Resource/id`. El sync consulta HAPI paginadamente y deriva UUID internos SHA-256 deterministas de logical source + tipo + `Resource.id` (bits RFC 4122; no usa IDs numéricos).

## Qué contiene

El bundle contiene Organization, jerarquía Location sala/cama, cinco Patient y cinco Encounter, tres abiertos (medicina, quirúrgico y compartido con traslado) y dos finalizados. Incluye datos sintéticos representativos; MedicationRequest expresa órdenes, no administraciones. Los IDs FHIR legibles y estables son `patient-med-01`, `patient-surg-02`, `patient-shared-03`, `patient-closed-04`, `patient-closed-05`; Encounter IDs `enc-med-ana`, `enc-surg-matias`, `enc-shared`, `enc-closed-ana`, `enc-closed-matias`.

| Episodio            | Escenario sintético                                                                                      |
| ------------------- | -------------------------------------------------------------------------------------------------------- |
| `enc-med-ana`       | Medicina: observaciones seriadas, paneles de laboratorio vinculados, condiciones y orden de medicamento. |
| `enc-surg-matias`   | Cirugía: procedimiento completado, órdenes y resultados/observaciones seriados.                          |
| `enc-shared`        | Traslado entre dos camas con observaciones seriadas y paneles de laboratorio.                            |
| `enc-closed-ana`    | Egreso tras observación breve; evidencia acotada al episodio.                                            |
| `enc-closed-matias` | Egreso tras procedimiento menor sintético; evidencia anterior al egreso.                                 |

El bundle se puede regenerar determinísticamente con `node scripts/fhir-sync/generate-demo-fixture.mjs` y validar con `node --test scripts/fhir-sync/demo-fixture.test.mjs`. Los recursos usan referencias transaccionales `PUT Resource/id` y un `fullUrl` absoluto coherente. Todo el contenido es inventado, exclusivamente demostrativo, no representa indicaciones ni una evaluación de calidad clínica y nunca debe emplearse para decisiones asistenciales.

## Cómo se conecta con la app

- La función Edge `clinical-record` consulta HAPI desde el servidor con `FHIR_SERVER_BASE_URL=http://hapi-fhir:8080/fhir`. Para el runtime Docker local, inicia Supabase y HAPI y luego ejecuta `pnpm fhir:gateway:serve`; el script conecta `carer-record-hapi-fhir` a `supabase_network_carer-record` con el alias `hapi-fhir` y usa `docker/hapi-fhir/gateway.env.example` (o el archivo local ignorado `gateway.env.local`). La conexión sobrevive a la recreación del runtime Edge por `functions serve`. No copies esta variable de servidor a Flutter.
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
