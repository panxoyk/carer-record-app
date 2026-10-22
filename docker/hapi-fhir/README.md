# Servidor HAPI FHIR de demostración

Servidor FHIR R4 local con 10 pacientes sintéticos para que cualquier persona del equipo vea en la app la misma lista de pacientes y las mismas fichas clínicas. Es solo para desarrollo: no tiene autenticación, guarda los datos en memoria y no debe recibir datos clínicos reales.

## Inicio rápido

Desde la raíz del repositorio, con Docker Desktop abierto:

```bash
pnpm fhir:up
pnpm fhir:logs
```

`pnpm fhir:up` levanta dos servicios:

- `hapi-fhir`: la imagen oficial `hapiproject/hapi`, publicada en `http://127.0.0.1:8080/fhir`.
- `hapi-seed`: una tarea de un solo uso que espera a que HAPI responda y carga [seed/demo-patients.json](seed/demo-patients.json).

La primera vez descarga las imágenes y HAPI tarda unos minutos en arrancar. En `pnpm fhir:logs` espera a ver «Pacientes de demostración cargados» (o «ya estaban cargados») y sal con `Ctrl+C`. Comprueba el resultado con:

```bash
curl "http://127.0.0.1:8080/fhir/Patient?_count=3"
```

Después, `pnpm fhir:sync` crea en Supabase local la hospitalización de cada paciente para que tengan bitácora. Ejecútalo tras cada `pnpm db:reset`.

## Comandos

| Necesidad                                  | Comando                            |
| ------------------------------------------ | ---------------------------------- |
| Levantar el servidor y cargar los datos    | `pnpm fhir:up`                     |
| Ver los logs                               | `pnpm fhir:logs`                   |
| Detener y borrar el servidor y sus datos   | `pnpm fhir:down`                   |
| Enlazar los pacientes con Supabase         | `pnpm fhir:sync`                   |
| Usar otro puerto (por ejemplo, el 8081)    | `HAPI_FHIR_PORT=8081 pnpm fhir:up` |
| Fijar la versión de la imagen de HAPI FHIR | `HAPI_FHIR_TAG=<tag> pnpm fhir:up` |

Los datos viven en memoria. Si el contenedor se reinicia o ejecutas `pnpm fhir:down`, se pierden; `pnpm fhir:up` vuelve a cargarlos. Como la base empieza vacía y el contenido es el mismo, los ids numéricos de los pacientes deberían repetirse; si cambian, ejecuta `pnpm fhir:sync` de nuevo.

## Qué contiene

Cada paciente trae sala, cama y fecha de ingreso en extensiones propias (`urn:hospital-simulado:fhir:ward`, `bed-number` y `admission-date`), un `Encounter` de hospitalización y recursos clínicos con los que la app arma la ficha: `Condition`, `AllergyIntolerance`, `MedicationRequest`, `Observation` (signos vitales), `Procedure`, `Immunization` y `DiagnosticReport`. Todos llevan la etiqueta `HTEST` (datos de prueba). El número de ficha (`CRA-0101` a `CRA-0110`) es un identificador de tipo `MR` con el sistema `urn:carer-record:demo:mrn`.

Los escenarios están descritos en la tabla «Datos de demostración» del [README principal](../../README.md). Son ficticios y no representan indicaciones clínicas reales.

## Cómo se conecta con la app

- La app lee el servidor con `FHIR_BASE_URL`. Su valor por defecto, `http://10.0.2.2:8080/fhir`, sirve para el emulador Android. Para iOS Simulator o un dispositivo con `adb reverse`, usa `--dart-define=FHIR_BASE_URL=http://127.0.0.1:8080/fhir`.
- La lista de pacientes y la ficha completa se piden directamente a HAPI. La bitácora vive en Supabase, y `pnpm fhir:sync` (que ejecuta [scripts/fhir-sync/generate-sync.mjs](../../scripts/fhir-sync/generate-sync.mjs)) crea ahí el paciente, la hospitalización, la ubicación y la asignación asistencial de cada paciente de HAPI. Los ids de Supabase se derivan del id numérico de FHIR, así que la app abre la bitácora sin consultas adicionales.

## Problemas frecuentes

- **El puerto 8080 está ocupado.** Detén el otro servidor (por ejemplo, un HAPI que corra en WSL o en otro contenedor) o usa `HAPI_FHIR_PORT`.
- **`pnpm fhir:sync` dice que no encuentra `supabase_db_*`.** Levanta Supabase con `pnpm db:start`.
- **La app no conecta con HAPI en un dispositivo físico.** Ejecuta `adb reverse tcp:8080 tcp:8080` y usa `127.0.0.1` en `FHIR_BASE_URL`.
- **La carga de datos falló.** `pnpm fhir:logs` muestra la respuesta de HAPI. Tras corregir el problema, ejecuta `pnpm fhir:down` y `pnpm fhir:up`.

## Límites

- La imagen usa `latest` por defecto. El equipo debe fijar `HAPI_FHIR_TAG` en una versión validada para que los resultados sean reproducibles.
- El servidor no autentica: cualquiera que alcance el puerto puede leer los datos. En el diseño objetivo, la autorización la decide RLS en Supabase.
- Para probar con volúmenes mayores (por ejemplo, un conjunto generado con Synthea), carga tus propios recursos en otro servidor y apunta `FHIR_BASE_URL` a él; el sync funciona con cualquier servidor cuyos pacientes tengan ids numéricos: `node scripts/fhir-sync/generate-sync.mjs <url-base-fhir> --apply`.
