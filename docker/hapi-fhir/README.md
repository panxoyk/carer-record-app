# Servidor HAPI FHIR de demostración

Servidor FHIR R4 local con 20 pacientes ficticios y episodios inpatient abiertos e históricos. Es solo desarrollo: no tiene autenticación y nunca debe recibir datos clínicos reales. La base H2 usa el datasource persistente del mismo HAPI fijado en `/data/hapi` dentro del volumen Docker `carer-record-hapi-data`.

## Inicio rápido

Desde la raíz del repositorio, con Docker Desktop abierto:

Terminal 1 inicia/reutiliza los servicios, sincroniza la estructura y mantiene la pasarela en foreground:

```bash
pnpm env:up
```

Terminal 2 inicia Flutter:

```bash
pnpm app:run
```

`app:run` no inicia contenedores ni gateway; admite argumentos normales de Flutter. El flujo de entorno inicia el servidor HAPI persistente y ejecuta bootstrap create-only desde Node del host:

- `hapi-fhir`: HAPI 8.12.0 fijado por digest, validado con FHIR R4 v4.0.1, publicado en `http://127.0.0.1:8080/fhir`.
- `scripts/fhir-sync/bootstrap-demo.mjs`: espera a HAPI y crea solo recursos sintéticos ausentes desde [seed/demo-patients.json](seed/demo-patients.json). Existentes se preservan, incluidas revisiones y cambios legítimos; identidades sin `HTEST` o relaciones Patient/Encounter incompatibles detienen la tarea.

La primera vez descarga las imágenes y HAPI tarda unos minutos en arrancar. `env:up` sincroniza estructura, asignaciones y pasarela. Al cerrar Flutter, los servicios siguen activos. `Ctrl+C` en terminal 1 cierra solo el gateway; contenedores y volúmenes quedan activos, por lo que hay que volver a ejecutar `pnpm env:up` antes de iniciar Flutter otra vez. Para operar HAPI por separado usa `pnpm fhir:down`, `pnpm fhir:logs` y el compose de Docker directamente. Comprueba el resultado con:

```bash
curl "http://127.0.0.1:8080/fhir/Patient?_count=3"
```

`pnpm env:up` proyecta Patient/Encounter/Location a las tablas estructurales de Supabase local y aplica las asignaciones declaradas. En una base limpia se esperan 20 pacientes/episodios: 14 abiertos (8 asignados y 6 sin asignar) y 6 cerrados históricos. No purga recursos FHIR ni reemplaza asignaciones existentes: solo crea una asignación si el par episodio/membresía aún no existe, incluidas asignaciones históricas vencidas. Los episodios cerrados con `validUntil` vencido no conceden lectura clínica por sí solos; el Administrador de demo puede verlos mediante sus permisos reservados y guardas RLS. Los UUID de Patient del fixture son constantes y válidos; los Encounter IDs se conservan para el manifest de asignaciones.

## Comandos

| Necesidad                                             | Comando                                                                                                      |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Iniciar entorno/gateway (terminal 1)                  | `pnpm env:up`                                                                                                |
| Iniciar solo Flutter (terminal 2)                     | `pnpm app:run`                                                                                               |
| Detener entorno y conservar volúmenes                 | `pnpm env:stop`                                                                                              |
| Ver los logs                                          | `pnpm fhir:logs`                                                                                             |
| Detener el servidor (conserva los datos del volumen)  | `pnpm fhir:down`                                                                                             |
| Respaldar datos sintéticos antes de una transición    | `node scripts/fhir-sync/hapi-data-transfer.mjs export --confirm-synthetic`                                   |
| Restaurar un archivo exportado, create-only           | `node scripts/fhir-sync/hapi-data-transfer.mjs restore --input=docker/hapi-fhir/exports/hapi-synthetic.json` |
| Borrar los datos persistentes (acción destructiva)    | `docker volume rm carer-record-hapi-data`                                                                    |
| Sincronizar/asignar manualmente (diagnóstico)         | `node scripts/fhir-sync/generate-sync.mjs --apply` y `--demo-assignments`                                    |
| Tests unitarios del mapper y SQL local                | `pnpm fhir:sync:test`                                                                                        |
| Integración HAPI aislada (Docker destructible opt-in) | `FHIR_DEMO_HAPI_INTEGRATION=1 pnpm integration:hapi`                                                         |
| Usar otro puerto (por ejemplo, el 8081)               | Configura `HAPI_FHIR_PORT=8081` en `.env` antes de `pnpm env:up`                                             |
| Sobrescribir la imagen fijada (solo versión validada) | `HAPI_FHIR_IMAGE` en el entorno antes de `pnpm env:up`                                                       |

La configuración del Spring Boot JPA starter sobrescribe el `jdbc:h2:mem:test_mem` de la imagen con `jdbc:h2:file:/data/hapi/hapi;DB_CLOSE_ON_EXIT=FALSE`; `/data/hapi` está en volumen nombrado y sobrevive al reinicio y a `pnpm fhir:down` (que no usa `down -v`). Un init-container dedicado prepara esa ruta para el UID/GID `65532:65532` usado por la imagen HAPI. Bootstrap y observaciones diarias usan `PUT` con `If-Match: W/"0"`: el HAPI fijado crea una identidad ausente y rechaza con conflicto cualquier revisión existente; `If-None-Match: *` no es create-only en esta versión. El fixture nunca reemplaza recursos existentes ni borra recursos ajenos. El sync consulta HAPI paginadamente y deriva UUID internos SHA-256 deterministas de logical source + tipo + `Resource.id` (bits RFC 4122; no usa IDs numéricos). `env:up` rechaza contenedores HAPI preexistentes que no monten ese volumen; `env:stop` también se niega a detenerlos. Ninguno los borra ni recrea. Antes de una transición manual, exporta solo si confirmas que el conjunto completo es sintético. La exportación archiva `_history` si el servidor lo permite; si no, marca el archivo como incompleto. La restauración conserva logical IDs, pero no afirma preservar los version IDs de origen. Los archivos de exportación contienen datos FHIR y son locales/ignorados por Git.

`integration:hapi` solo se ejecuta cuando se opta explícitamente con `FHIR_DEMO_HAPI_INTEGRATION=1`. Crea un contenedor y volumen con nombres de prueba únicos, limita el puerto a loopback y elimina únicamente esos recursos; necesita que las imágenes fijadas estén ya disponibles localmente. No usa ni detiene el HAPI de desarrollo.

## Transición manual segura

La instancia de desarrollo actual **no está migrada**; no ejecutes transición automáticamente al iniciar la app. No uses el comando de borrado de volumen como paso de migración. Para ensayar una transición, conserva el servidor y volumen actuales intactos y usa un HAPI de staging con nombre y volumen dedicados, sin datos de producción:

1. Confirma que todo el conjunto origen es sintético y exporta explícitamente: `node scripts/fhir-sync/hapi-data-transfer.mjs export --confirm-synthetic`. Guarda el archivo exportado en una ruta local ignorada por Git; no lo compartas ni lo versionees.
2. Revisa el reporte de exportación, incluidos `historyComplete` y los conteos de recursos/historia. Si historia completa es falsa o el reporte no coincide con lo esperado, detén la transición y conserva el origen; no afirmes que las revisiones están respaldadas.
3. Prepara un contenedor HAPI de staging separado con el mismo digest HAPI 8.12.0, un volumen Docker nuevo y dedicado y la configuración persistente documentada. No conectes ni reutilices el volumen actual para el ensayo.
4. Restaura en staging con `node scripts/fhir-sync/hapi-data-transfer.mjs restore --input=<ruta-del-export-ignorado>` y valida allí identidades, conteos y consultas antes de considerar cualquier cambio posterior.
5. Mantén el servidor y volumen anteriores hasta completar y revisar esa validación. La restauración preserva `Resource.id` lógico cuando es posible; no preserva necesariamente `meta.versionId`. El archivo es un archivo de recursos/historia FHIR, no un respaldo completo de la base H2, esquema o configuración. Si el servidor no exportó tombstones de borrado, esos borrados tampoco se reconstruyen; no se garantiza restaurar todas las revisiones fuente.

No hay purga ni recreación implícita: el arranque normal protege el contenedor HAPI existente antes de considerar la composición y falla ante un datasource/volumen incompatible, sin detenerlo ni recrearlo. El volumen nuevo se administra manualmente y no reemplaza automáticamente al existente.

## Qué contiene

El bundle contiene Organization, jerarquía Location sala/cama, 20 Patient y 20 Encounter: 14 abiertos y 6 cerrados históricos con `validUntil`. Tras sync en base limpia, 8 episodios abiertos tienen asignación demo y 6 quedan sin asignar. Incluye recursos clínicos sintéticos relacionados; los IDs Patient son UUID fijos y los Encounter IDs se mantienen para assignments. MedicationRequest expresa órdenes ficticias, no administraciones.

| Episodio            | Escenario sintético                                                                                      |
| ------------------- | -------------------------------------------------------------------------------------------------------- |
| `enc-med-ana`       | Medicina: observaciones seriadas, paneles de laboratorio vinculados, condiciones y orden de medicamento. |
| `enc-surg-matias`   | Cirugía: procedimiento completado, órdenes y resultados/observaciones seriados.                          |
| `enc-shared`        | Traslado entre dos camas con observaciones seriadas y paneles de laboratorio.                            |
| `enc-closed-ana`    | Egreso tras observación breve; evidencia acotada al episodio.                                            |
| `enc-closed-matias` | Egreso tras procedimiento menor sintético; evidencia anterior al egreso.                                 |

El bundle se puede regenerar determinísticamente con `node scripts/fhir-sync/generate-demo-fixture.mjs` y validar con `node --test scripts/fhir-sync/demo-fixture.test.mjs`. Los recursos usan referencias transaccionales `PUT Resource/id` y un `fullUrl` absoluto coherente. Todo el contenido es inventado, exclusivamente demostrativo, no representa indicaciones ni una evaluación de calidad clínica y nunca debe emplearse para decisiones asistenciales. Los escenarios disponibles se definen en el fixture fuente `seed/demo-patients.json`; evita tratar snapshots o listas derivadas como catálogo clínico.

## Cómo se conecta con la app

- La función Edge `clinical-record` consulta HAPI desde el servidor con `FHIR_SERVER_BASE_URL=http://hapi-fhir:8080/fhir`. Esta configuración pertenece al env-file de la función, no a `.env` ni Flutter: se usa `docker/hapi-fhir/gateway.env.local` si existe, con `gateway.env.example` como fallback. `pnpm env:up` conecta `carer-record-hapi-fhir` a `supabase_network_carer-record` con el alias `hapi-fhir`. La red y alias deben estar conectados también al reutilizar una pasarela ya activa.
- La publicación de HAPI permanece ligada a `127.0.0.1:8080` para herramientas del host. El contenedor del dispositivo no obtiene ruta al alias `hapi-fhir` ni evita la autorización Edge/RPC; la función solo consulta tras validar sesión y autorización RLS. La configuración móvil directa ADR-019 ya no es el camino de la ficha protegida.
- `env:up` genera y aplica SQL local como propietario Docker y aplica asignaciones del manifest de forma idempotente. No infiere profesionales desde autoría FHIR y no reactiva vínculos revocados.

## Problemas frecuentes

- **El puerto 8080 está ocupado.** Detén el otro servidor (por ejemplo, un HAPI que corra en WSL o en otro contenedor) o usa `HAPI_FHIR_PORT`.
- **El sync dice que no encuentra `supabase_db_*`.** Inicia el flujo normal con `pnpm env:up`; para diagnóstico, ejecuta `pnpm exec supabase start`.
- **La función no conecta con HAPI.** Comprueba Supabase y HAPI con `pnpm env:up`, y revisa su estado antes de reiniciar el flujo; no cambies el puerto publicado a una interfaz accesible por la red.
- **La carga de datos falló.** `pnpm fhir:logs` muestra la respuesta de HAPI. Tras corregir el problema, ejecuta `pnpm fhir:down` y vuelve a iniciar `pnpm env:up`.

## Límites

- La imagen predeterminada está fijada a HAPI 8.12.0 por digest y fue validada con FHIR R4 v4.0.1.
- El servidor no autentica: cualquiera que alcance el puerto puede leer los datos. En el diseño objetivo, la autorización la decide RLS en Supabase.
- El puerto se publica solo en `127.0.0.1` por compatibilidad con herramientas locales. El acceso servidor usa una red Docker privada entre runtime Edge y HAPI; esto es configuración de desarrollo local, no un despliegue productivo.
- Las asignaciones fixture autorizan lectura de demo; no representan inferencias clínicas ni se crean con el sync estructural.
- Los fixtures SQL legacy se conservan para las pruebas existentes; la lista de demostración usa `fhir_clinical_census_by_hospitalization` y solo muestra episodios FHIR enlazados y autorizados.
