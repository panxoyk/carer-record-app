# Plan de ejecución: ASR local y síntesis local para hitos de bitácora

## Propósito

Documento de traspaso para ejecutar en otra sesión la arquitectura ya decidida por
el usuario para la primera versión del producto:

1. **ASR local con `sherpa_onnx`**: el profesional dicta un hito, se transcribe en
   el dispositivo y se publica **solo el texto final confirmado**. El audio nunca
   sale del teléfono.
2. **Síntesis local con un modelo GGUF**: un modelo en el dispositivo mejora el
   texto que el profesional escribió a mano en la bitácora. Sin egreso de texto.

Las decisiones de este documento **están tomadas**. No reabrir la discusión de
motor, proveedor ni modelo durante la ejecución: la sesión ejecutora debe
implementar, medir y documentar.

El plan **sustituye la provisión de audio almacenado de ADR-015** (bucket privado
con reproducción por URL firmada). Esa provisión es una decisión vigente y
verificada, no un defecto: el reemplazo se documenta con ADR-016, que la
sustituye en parte (ver "Estado actual").

## Reglas de la sesión ejecutora

Leer antes de tocar nada:

- `AGENTS.md` — separación `data/domain/presentation`, RLS como autoridad, no
  editar migraciones aplicadas, cambios clínicos en orden
  permisos → datos/RLS → pruebas → repositorio → UI.
- `docs/foundation/README.md` — estados Confirmado/Decidido/Propuesto/Pendiente.
- `docs/foundation/09-audio-ai-ner.md` — contrato de audio, ASR y síntesis.
- `docs/foundation/decisions/adr-015-hitos-bitora-audio.md` — contrato vigente
  del corte de hitos (texto + audio almacenado) que este plan sustituye en parte.
- `docs/foundation/flows/audio-note.md` y `flows/text-note.md` — contratos de flujo.

Prohibiciones que aplican a todo el plan:

- Datos clínicos reales en cualquier fixture, log, prompt, modelo o captura.
  Solo sintéticos.
- Persistir audio, transcripción cruda, mapa de tokens o prompt fuera del
  dispositivo.
- Fallback a ASR o LLM cloud si el motor local falla. Se informa el fallo.
- Editar migraciones ya aplicadas. Todo esquema nuevo es migración aditiva.

## Estado actual verificado

El bloqueador de persistencia clínica **ya está resuelto** en trabajo sin
commitear en `main` (HEAD `3d58988`, sin commits creados por esa sesión). No
rehacerlo.

| Pieza                                                                                 | Ubicación                                                        | Estado        |
| ------------------------------------------------------------------------------------- | ---------------------------------------------------------------- | ------------- |
| ADR-015 (hitos texto + audio almacenado)                                              | `docs/foundation/decisions/adr-015-hitos-bitora-audio.md`        | Aceptada      |
| Tabla `context_notes` + RLS + grants                                                  | `supabase/migrations/20261012000000_context_note_milestones.sql` | Sin commitear |
| pgTAP de hitos (27 planes)                                                            | `supabase/tests/context_notes_milestones.test.sql`               | Sin commitear |
| Dominio Flutter `context_note`                                                        | `app/lib/domains/context_note/`                                  | Sin commitear |
| Botón de hito + timeline mezclado                                                     | `app/lib/domains/patient/presentation/patient_screens.dart`      | Sin commitear |
| Permisos `context.note.*` en roles seed                                               | `supabase/seed.sql`                                              | Sin commitear |
| `record ^6.2.1` (5.2.1 era conjunto no compilable)                                    | `app/pubspec.yaml`, `app/pubspec.lock`                           | Sin commitear |
| `minSdk 23` (exigencia del merger de `record_android`)                                | `app/android/app/build.gradle.kts`                               | Sin commitear |
| `just_audio ^0.9.4` (reproducción) y `RECORD_AUDIO`                                   | `app/pubspec.yaml`, `AndroidManifest.xml`                        | Sin commitear |
| `usesCleartextTraffic` (reproducción nativa sobre HTTP local de dev; inerte en HTTPS) | `app/android/app/src/main/AndroidManifest.xml`                   | Sin commitear |

Evidencia de validación del corte vigente:

- `pnpm db:test` verde: 418 pruebas, 11 archivos (incluidas las 27 de hitos).
- `pnpm app:analyze` clean; `pnpm app:test` 101/101.
- E2E en emulador (build debug con dart-defines): hito de texto y hito de audio
  creados desde la UI, fila en timeline, filas en `context_notes`, objeto `.m4a`
  en `storage.objects`, reproducción verificada tras la corrección
  `usesCleartextTraffic`.

### Estado normativo: la provisión de audio almacenado es ADR-015, no un defecto

La sesión que implementó el corte actual también decidió y documentó la
persistencia del audio de hitos: **ADR-015** (Aceptada, 2026-10-12) sustituye en
parte la regla de no subida de ADR-006 y la de no persistencia remota de ADR-010
**limitado al audio de hitos confirmados**; ADR-006 y ADR-010 quedaron marcadas
"en parte sustituida por ADR-015" y `flows/audio-note.md` distingue
explícitamente el flujo de dictado (su audio nunca sale del dispositivo) del
corte de hitos. Por tanto la fundación es coherente y no hay contradicción que
corregir.

Este plan no invoca ninguna inconsistencia: **reemplaza una decisión vigente con
otra posterior**. La ADR-016 documentará la sustitución parcial de ADR-015 (su
punto 2, audio almacenado) y reactivará la regla de no subida de ADR-006 para el
flujo de dictado, que pasa de experimental a ser el flujo real del hito de audio.

Nota documental pendiente: `09-audio-ai-ner.md:11` ("el audio permanece en el
dispositivo y nunca se carga a Supabase…") rige el pipeline de dictado/ASR/NER y
no es contradicha por ADR-015, pero se recomienda añadir allí la referencia
cruzada a ADR-015 para evitar lecturas contradictorias (incorporar en Fase 7).

Infraestructura a retirar en la Fase 2 (migración
`20261012000000_context_note_milestones.sql`, no editarla):

- Bucket `context-note-audio` y su inserción: `:104-108`
- Funciones `can_store_context_note_audio` y `can_read_context_note_audio`:
  `:110-148`
- Dos políticas sobre `storage.objects`: `:150-162`
- Columnas `storage_path` (`:22-23`) y `audio_duration_ms` (`:24-25`) y sus
  grants de columna: `:168-174`
- Constraint `context_notes_single_form`: `:34-38`
- `uploadBinary`/`remove`/`createSignedUrl`:
  `app/lib/domains/context_note/data/context_note_repository.dart:44-82`
- Reproducción desde Storage en `_TimelineRowState`:
  `app/lib/domains/patient/presentation/patient_screens.dart`
- Columnas `audio_storage_path`/`audio_duration_ms` y el literal `'Hito de
audio'` en la vista `clinical_timeline_by_hospitalization`: `:189-190`,
  `:196-200`

`just_audio` **se conserva**: hoy reproduce el audio almacenado desde Storage;
después de este plan solo servirá para escuchar el audio local antes de
confirmar (`flows/audio-note.md`). `record` **se conserva**.

## Arquitectura objetivo

```text
DISPOSITIVO — ningún texto ni audio de IA sale a la red
├── record                 captura en sandbox
├── sherpa_onnx            ASR local ES, offline, con confianza por segmento
├── just_audio             escucha local pre-confirmación
├── flutter_secure_storage temporales cifrados, outbox
└── [F5] llamadart + GGUF  mejora de texto, NER y resumen

SERVIDOR — solo la nota final confirmada
├── context_notes          ya implementado; storage_path → transcription_metadata
│                          (ADR-016 sustituye el punto 2 de ADR-015)
├── RLS + pgTAP            ya implementado, se reajusta en Fase 2/3
└── clinical_timeline_by_hospitalization  ya mezcla hitos

A RETIRAR (decisión de ADR-015 vigente, sustituida por ADR-016)
├── bucket context-note-audio + 2 políticas Storage
└── supabase/functions/clinical-summary  (stub 501, nunca invocado)
```

## Fase 0 — Cerrar el trabajo sin commitear (bloqueante para todo)

El trabajo actual es un cambio lógico independiente y debe quedar cerrado antes
de mezclar fases posteriores. Incluye también el soporte nativo del corte:
`RECORD_AUDIO` + `usesCleartextTraffic` en `AndroidManifest.xml`, `minSdk 23`
en `build.gradle.kts` y la serie `record ^6.2.1` en `pubspec`/lock.

1. Ejecutar la validación de las capas tocadas:

   ```bash
   pnpm db:reset
   pnpm db:test
   pnpm db:lint
   pnpm app:format:check && pnpm app:analyze && pnpm app:test
   pnpm integration:local
   ```

2. Si todo pasa, crear **un** commit con el corte de hitos de bitácora
   (escritura clínica + UI + audio almacenado según ADR-015). Título sugerido:
   `feat(app): publish bitácora milestones as clinical context notes`.
3. Si algo falla, arreglarlo antes de continuar.

Criterio de salida: commit creado y suite verde.

## Fase 1 — ADR

Ninguna fase posterior cambia comportamiento antes de esto.

1. Crear `docs/foundation/decisions/adr-016-asr-local-transcripcion-confirmada.md`.
   - Estado: Aceptada.
   - Decide: ASR local con sherpa-onnx; el audio y la transcripción son
     artefactos técnicos locales; se persiste **solo la nota confirmada por su
     autor**; procedencia `input_method = 'audio'` con
     `transcription_metadata` que nunca contiene el texto crudo.
   - Relación: **sustituye en parte a ADR-015** (punto 2, audio almacenado en
     bucket privado) y reactiva la regla de no subida de ADR-006 para el flujo
     de dictado, que pasa de experimental a flujo de producción del hito de
     audio. ADR-007/008/009/010 quedan con su alcance actual.
   - Nota: la migración `20261012000000_context_note_milestones.sql:7` ya
     referencia a ADR-015 (que existe); la nueva referencia a ADR-016 se escribe
     en la migración aditiva de la Fase 2, nunca editando la aplicada.
2. Crear
   `docs/foundation/decisions/adr-017-sintesis-local.md` como **sustitutiva** de
   ADR-008 y ADR-009.
   - Decide: síntesis íntegramente local con GGUF; se retiran tokenización
     reversible, Edge Function de síntesis y proveedor cloud.
   - Consecuencias a declarar: el mapa token-valor deja de existir porque nada
     sale del dispositivo; `Q-AI-03` (procedencia sintética verificable en
     runtime) deja de ser bloqueante porque no hay egreso; se elimina
     `clinical-summary`.
   - Enlazar desde ADR-008 y ADR-009 como sustituidas.
3. Actualizar `docs/foundation/decisions/index.md`: filas nuevas ADR-016 y
   ADR-017 con su estado e implementación observada, y la fila de ADR-015 pasa a
   "Aceptada, en parte sustituida por ADR-016".
4. Cerrar `Q-ASR-01`, `Q-ASR-02`, `Q-NER-02`, `Q-AI-01`, `Q-AI-02` y `Q-AI-03`
   en `docs/foundation/appendices/open-questions.md` con decisión, responsable,
   fecha y evidencia. Cerrar además `Q-AUDIO-01` y retirar `RK-028`
   (`appendices/risk-register.md`): sin audio crudo persistido no queda retención
   de hitos que gobernar; si surgiera otra necesidad de retención, reabrir con
   evidencia.

Criterio de salida: ADR-016 y ADR-017 aceptadas, index y preguntas actualizados.

## Fase 2 — Migración aditiva: audio local, sin Storage

Crear `supabase/migrations/<timestamp>_context_note_local_transcription.sql`.
No editar `20261012000000_context_note_milestones.sql`.

1. Añadir `transcription_metadata jsonb` con constraint de objeto y tamaño
   máximo. Campos permitidos: `asr_engine`, `asr_model`, `asr_model_version`,
   `asr_model_checksum`, `asr_parameters`, `duration_ms`, `mean_confidence`,
   `low_confidence_segments`, `pipeline_version`. **Prohibido** storing texto.
2. Retirar `storage_path` (`:22-23`), `audio_duration_ms` (`:24-25`) y sus grants
   de columna (`:168-174`); su contenido en `storage.objects` se drena antes de
   eliminar el bucket (ver 3).
3. Eliminar el bucket `context-note-audio` (incluida la inserción de `:104-108`),
   las dos políticas de `storage.objects` (`:150-162`) y las funciones
   `can_store_context_note_audio` / `can_read_context_note_audio`
   (`:110-148`).
4. Reemplazar el constraint `context_notes_single_form` (`:34-38`): en
   `input_method = 'audio'` el `content` pasa a ser obligatorio (es la nota
   confirmada) y el `transcription_metadata` no nulo. En `text`, `content`
   obligatorio y metadata nula.
5. Ajustar el view `clinical_timeline_by_hospitalization`: `summary` debe
   exponer el `content` confirmado también para hitos de audio, no el literal
   `'Hito de audio'` (`:196`). Conservar `source_kind`. Retirar
   `audio_storage_path` y `audio_duration_ms` de la proyección (`:189-190`,
   `:199-200`), o sustituirlos por las columnas de metadatos no sensibles que
   decida la ADR-016.
6. Actualizar `supabase/seed.sql`: los hitos de audio sintéticos deben insertarse
   con `content` y `transcription_metadata`, nunca con `storage_path`.
7. Declarar en `docs/foundation/08-data-model.md:717-729` la desviación
   consciente: la implementación usa `id uuid` propio y omite la cabecera
   `clinical_records` y `corrects_note_id`. Marcarlo **Decidido** o
   **Propuesto**, nunca dejarlo silencioso.

Criterio de salida: `pnpm db:reset` y `pnpm db:test` verdes; ningún objeto de
audio en `storage.objects` es alcanzable; el hito de texto del corte vigente no
regresa (mantiene `content` y `client_event_id` idempotente).

## Fase 3 — pgTAP del contrato corregido

Actualizar `supabase/tests/context_notes_milestones.test.sql` (existe, es
nuevo y sin commitear: se puede editar). Ajustar el `plan()` al número real de
pruebas.

Casos obligatorios:

- Hito de audio con `content` + `transcription_metadata` es aceptado.
- Hito de audio **sin** `content` viola el constraint.
- Hito de texto con `transcription_metadata` viola el constraint.
- Hito de texto sin cambios en el corte vigente (regresión): aceptado y
  proyectado en el timeline.
- `transcription_metadata` no objeto o sobredimensionado viola el constraint.
- El bucket `context-note-audio` **no existe**.
- No existe ninguna política de `storage.objects` para ese bucket.
- Reproducir el mismo `client_event_id` lanza `23505` (idempotencia).
- Fuera de alcance asistencial → `42501`.
- Otro tenant → `42501`.
- Membresía suspendida → `42501` en escritura y `0` filas visibles.
- Sin roles clínicos → `42501` y `0` filas en el timeline.
- Autor ajeno no lee borradores ajenos.
- `update` y `delete` siguen denegados en `42501`.
- El administrador de demo lee hitos pero no escribe.
- La vista del timeline sigue siendo `security_invoker` y `security_barrier`.

Añadir además el test de privacidad que exige la fundación
(`flows/audio-note.md`): una aserción explícita de que **no existe** bucket,
política ni columna capaz de transportar audio.

Criterio de salida: `pnpm db:test` verde y ningún caso omitted.

## Fase 4 — sherpa_onnx en la app

1. Cerrar el spike **SP-01** antes de habilitar la UI, según
   `docs/foundation/09-audio-ai-ner.md:55-63`. El spike es el gate; la feature
   falla cerrada si el motor no está disponible
   (`flows/audio-note.md`).
2. Añadir `sherpa_onnx` a `app/pubspec.yaml`. Paquete verificado:
   `sherpa_onnx ^1.13.8`, Apache-2.0, arm64 Android e iOS, ~65.5k descargas.
   Verificar compatibilidad con el SDK actual del repo antes de fijar la versión.
3. Distribuir el modelo español con versión y checksum verificable. No commitear
   pesos de modelo al repositorio. Registrar origen, licencia y checksum en un
   manifiesto versionado, no en el código.
4. Reestructurar el dominio siguiendo la separación del repo:
   - `app/lib/domains/context_note/domain/` — entidad y estados del ciclo de vida
     (`recording`, `transcribing_local`, `ready_to_confirm`, `published`,
     `failed`, `discarded`, según `flows/audio-note.md`)
   - `app/lib/domains/context_note/data/` — `AsrEngine` detrás de interfaz
     independiente del motor. El dominio no conoce SDK, formato nativo ni ruta de
     modelo (`ADR-007:28`).
   - `app/lib/domains/context_note/presentation/` — el bottom sheet existente
5. Cambiar el flujo de `milestone_editor_sheet.dart`:
   - grabar → transcribir localmente → mostrar transcripción en campo editable →
     el autor escucha con `just_audio`, corrige y confirma → recién ahí persistir
   - la transcripción **nunca** se persiste por sí sola
   - conservar confianza por segmento cuando el motor la entregue
     (`ADR-007:15`); si un segmento es incierto, marcarlo visible
6. Añadir `flutter_secure_storage` como **dependencia directa** para temporales
   cifrados y outbox. Hoy el storage seguro solo llega de forma transitiva vía
   `supabase_flutter` (persistencia de la sesión de auth); los artefactos de
   dictado (audio, transcripción, outbox) requieren la dependencia explícita.
7. Purgar audio, transcripción y temporales al confirmar, descartar, cerrar
   sesión o expirar (`09-audio-ai-ner.md:18`). La limpieza debe ser idempotente.
8. Quitar de `context_note_repository.dart` todo el código de Storage
   (`:44-82`). La escritura pasa a ser un único `insert` con `content` y
   `transcription_metadata`.
9. Quitar de `_TimelineRowState` en `patient_screens.dart` la reproducción desde
   Storage. La nota confirmada se muestra como texto.

Criterio de salida:

- Inspección de red demuestra que no se transmite audio ni transcripción original.
- Modo avión: grabar, transcribir y revisar funcionan sin red.
- Confirmar, descartar, cerrar sesión y vencer eliminan todos los temporales.
- ASR corre sin red en las plataformas soportadas.
- `pnpm app:analyze`, `pnpm app:test`, `pnpm app:format:check` verdes.

## Fase 5 — Síntesis local

Depende de un cambio de SDK. Tratar como PR independiente y anterior a esta fase.

1. **Upgrade de Flutter.** `app/pubspec.yaml:8` fija `flutter: "3.29.3"` y
   `:7` `sdk: ">=3.7.0 <4.0.0"`. El runtime Dart on-device mejor soportado
   (`llamadart`) exige Dart ≥3.10.7 y Flutter ≥3.38.0. Subir el SDK es
   **prerrequisito** y tarea propia, con su propia validación completa
   (`app:analyze`, `app:test`, `integration:local`, build Android e iOS).
2. Añadir `llamadart` y el modelo GGUF de redacción. No commitear los pesos.
   Entrega del modelo: descarga explícita con progreso en el primer arranque o
   preinstalación. Sin esto la feature no es usable en una demo.
3. Implementar `SynthesisProvider` **local** como puerto del dominio, con
   adaptador GGUF y fake determinista para pruebas
   (`ADR-009:13`, ahora bajo ADR-017). El dominio no importa SDK ni tipos del
   runtime.
4. Usos, en este orden:
   - mejorar el texto del hito escrito a mano
   - NER local para señalar entidades al autor, **sin** tokenización reversible
   - resumen de periodo (ADR-011) como última adición
5. Salida estructurada cuando el modelo la soporte; el caso de uso controla
   timeout, cancelación, idempotencia, versión de prompt/modelo y códigos de
   error estables.
6. Si el motor local falla o el modelo no está instalado, el hito se publica
   directo. La asistencia nunca bloquea la escritura clínica.
7. Medir sobre corpus sintético en español clínico: latencia, pico de RAM,
   batería, temperatura y tamaño de descarga. Registrar resultados. No afirmar
   calidad clínica.

Criterio de salida:

- El dominio no importa SDK ni tipos del runtime; cambiar fake por adaptador no
  cambia el caso de uso.
- Sin egreso de texto del hito.
- Un hito se publica incluso con el modelo ausente.
- Suite de app verde sobre el SDK actualizado.

## Fase 6 — Retiro de la síntesis cloud

1. Eliminar `supabase/functions/clinical-summary/`.
2. Actualizar `supabase/functions/deno.json`, el lock y los scripts de
   `package.json:27-30`, que hoy lo incluyen en `functions:typecheck`.
3. Verificar que ninguna referencia a `clinical-summary` sobreviva en `app/`,
   `scripts/`, `docs/` ni `.github/`.
4. Regenerar tipos si aplica: `pnpm functions:types:generate`.

Criterio de salida: `pnpm functions:check` verde sin la función; sin referencias
residuales.

## Fase 7 — Cierre documental

Actualizar, sin mantener resúmenes paralelos del estado implementado:

| Documento                                                 | Cambio                                                                                                                                     |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `docs/foundation/decisions/index.md`                      | Filas ADR-016/017; ADR-015 pasa a "en parte sustituida por ADR-016"                                                                        |
| `docs/foundation/decisions/adr-015-hitos-bitora-audio.md` | Marcar "en parte sustituida por ADR-016" con fecha                                                                                         |
| `docs/foundation/03-scope.md`                             | Incrementos C y D pasan a Confirmado con evidencia                                                                                         |
| `docs/foundation/09-audio-ai-ner.md`                      | Rework: NER local sin tokenización, síntesis local; añadir referencia cruzada a ADR-015 en `:11` (audio de dictado vs. audio de hito)      |
| `docs/foundation/flows/audio-note.md`                     | Estados reales, destino de la transcripción y fin de la distinción temporal con ADR-015 (el dictado pasa a ser el flujo del hito de audio) |
| `docs/foundation/flows/text-note.md`                      | Ruta de síntesis local                                                                                                                     |
| `docs/foundation/08-data-model.md`                        | Desviación de `clinical_records` y `context_notes`                                                                                         |
| `docs/foundation/12-delivery-roadmap.md`                  | V3, V4, V5 con estado real                                                                                                                 |
| `docs/foundation/appendices/risk-register.md`             | Retiro de RK-028; RK-007 y riesgos de tamaño/batería/SDK                                                                                   |
| `docs/foundation/appendices/open-questions.md`            | Preguntas resueltas con evidencia (incluida Q-AUDIO-01)                                                                                    |
| `docs/foundation/appendices/requirements-traceability.md` | RQ → ADR → flujo → entidad → prueba                                                                                                        |
| `docs/foundation/appendices/evidence-index.md`            | Resultados del spike y del benchmark                                                                                                       |
| `docs/todo.md`                                            | Bloques nuevos y estados                                                                                                                   |

Validar: `pnpm docs:format:check`, `pnpm docs:lint`, `git diff --check`.

Criterio de salida: ninguna capacidad marcada como implementada sin código y
prueba reproducibles (`docs/foundation/README.md:141`).

## Orden y dependencias

```text
F0 commit del trabajo actual
 └─> F1 ADR
      └─> F2 migración
           └─> F3 pgTAP
                └─> F4 sherpa_onnx  ──┐
                     F5 upgrade SDK ──┴─> F6 retirar clinical-summary
                                              └─> F7 documentación
```

F4 y el upgrade de F5 pueden avanzar en paralelo; F6 espera a F5.

## Riesgos a vigilar

| Riesgo                                                        | Mitigación                                                                        |
| ------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| El audio vuelve a subirse por una ruta no revisada            | Test de privacidad que falle si existe bucket, política o columna de audio        |
| La transcripción se persiste como nota sin revisión del autor | La nota solo nace tras confirmación; `input_method` y provenance auditables       |
| El reemplazo del audio almacenado regresa el hito de texto    | Caso pgTAP de regresión en F3 y pruebas de app del corte vigente antes del retiro |
| Upgrade de Flutter rompe dominios no relacionados             | PR aislado con validación completa antes de integrar F5                           |
| El modelo GGUF degrada el texto clínico en lugar de mejorarlo | La síntesis es opcional y no bloquea; medir antes de afirmar                      |
| Falsas transcripciones cambian significado clínico            | `ADR-007:15`: la transcripción es borrador editable con confianza por segmento    |
| El repo acumuló trabajo sin commitear que se pierde           | F0 cierra y versiona antes de cualquier otro cambio                               |

## Definición de terminado

- Ningún audio ni transcripción cruda sale del dispositivo ni se persiste.
- La única nota persistida es la que su autor confirmó.
- La provisión de audio almacenado de ADR-015 quedó retirada de forma completa
  (bucket, políticas, funciones, columnas, grants y reproducción en UI) y el
  hito de texto no regresa.
- RLS deniega publicación sin permiso, con membresía suspendida, a otro autor,
  fuera de alcance o en otro tenant, con pruebas que lo demuestren.
- No existe proveedor cloud de síntesis ni Edge Function de síntesis.
- Todo el corte está versionado en commits lógicos independientes.
- La documentación refleja lo implementado, no lo previsto.
