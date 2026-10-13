# ADR-016: ASR local y transcripción confirmada como único registro del hito de audio

- Estado: Aceptada
- Fecha: 2026-10-12
- Alcance: captura de audio en la bitácora, transcripción en el dispositivo y persistencia del hito de audio; sustituye en parte el punto 2 de ADR-015
- Relación: **sustituye en parte a ADR-015** (punto 2, audio almacenado en bucket privado) y reactiva la regla de no subida de ADR-006 para el flujo de dictado, que pasa de experimental a flujo de producción del hito de audio; depende de ADR-005, ADR-007, ADR-013, ADR-014 y ADR-017; ADR-008/009/010 quedan con su alcance actual hasta su sustitución por ADR-017

## Contexto

ADR-015 decidió que el hito de audio se almacenaba crudo en el bucket privado `context-note-audio` y se reproducía desde la bitácora. Eso resuelve el registro, pero conserva el activo de mayor exposición del producto en infraestructura remota: el audio de un hito puede contener identidad, contexto y voces de terceros, y persiste mientras exista la fila. ADR-015 dejó explícitamente la transcripción en el dispositivo como capacidad futura condicionada a ADR-007.

Al mismo tiempo, el único camino para evaluar la hipótesis académica de ASR local (ADR-007, `09-audio-ai-ner.md`) exigía un flujo de dictado que no podía publicar nada, porque persistir el audio estaba prohibido. El prototipo tenía, por tanto, un bucle cerrado: la única forma de probar ASR local era una ruta que no podía llegar al producto.

## Decisión

1. **El audio y la transcripción son artefactos técnicos locales.** El audio capturado no se sube a Supabase, a una Edge Function ni a ningún proveedor. La transcripción derivada tampoco se persiste en servidor ni se envía a la red. Se reactiva para este flujo la regla de no subida de ADR-006 y la de no persistencia remota de ADR-010.
2. **Se persiste solo la nota confirmada por su autor.** Un hito de audio nace únicamente después de que la persona grabe, escuche la transcripción, la revise y la confirme. `content` es obligatorio en `input_method = 'audio'` y es el texto que el autor aprobó, no la salida cruda del motor. La transcripción nunca se persiste por sí sola y no existe publicación automática.
3. **La procedencia es auditable sin contenido.** La fila se marca `input_method = 'audio'` y lleva un `transcription_metadata` jsonb acotado a campos técnicos no sensibles: `asr_engine`, `asr_model`, `asr_model_version`, `asr_model_checksum`, `asr_parameters`, `duration_ms`, `mean_confidence`, `low_confidence_segments` y `pipeline_version`. **Prohibido** almacenar texto, tokens, fragmentos, prompts o respuestas. El objeto tiene constraint de forma y tamaño máximo en la base de datos, no solo en el cliente.
4. **El motor es local y behind a puerto.** `sherpa_onnx` (Apache-2.0) implementa `AsrEngine`; el dominio no conoce SDK, formato nativo ni ruta de modelo (ADR-007:28). El modelo se distribuye con versión y checksum verificable y su manifiesto está versionado en el repositorio; los pesos no se commitean.
5. **Falla cerrada, nunca a la red.** Si el motor local no está disponible, falla, o el modelo no está instalado, la app informa el fallo y ofrece el hito textual. No existe fallback a ASR cloud. No se sustituye un motor local por uno remoto sin una ADR nueva.
6. **La transcripción es borrador editable con confianza por segmento.** Cuando el motor entrega confianza, los segmentos inciertos se marcan visiblemente para el autor (ADR-007:15). Una transcripción errónea no debe poder cambiar el significado clínico de un hito sin que la persona lo vea.
7. **Los temporales se purgan siempre.** Audio, transcripción, borradores, outbox y archivos del motor se eliminan al confirmar, descartar, cerrar sesión o expirar; el borrado es idempotente y un barrido recupera residuos tras un cierre inesperado (ADR-010).
8. **RLS sigue siendo la autoridad.** Publicar exige perfil y membresía activos, `context.note.create` y `context.note.confirm` efectivos, alcance sobre la hospitalización según ADR-013 y `author_id = auth.uid()`. La app no persiste nada del flujo local; no hay ruta de escritura para audio ni transcripción.
9. **La reproducción local sustituye a la reproducción remota.** `just_audio` sirve para que el autor escuche la grabación antes de confirmar. El hito publicado se muestra como texto confirmado en la bitácora; no existe reproducción de audio desde la bitácora.

## Alternativas consideradas

- **Mantener el bucket privado (ADR-015):** conserva fidelidad y reproducción simple, pero mantiene el activo más sensible en infraestructura remota y no permite evaluar ASR local.
- **Guardar solo la transcripción remota:** reduce el volumen, pero persiste contenido clínico sin revisión del autor y reabre el problema de exposición con menor control.
- **Mantener audio almacenado y añadir transcripción local:** maximizes fidelidad, pero conserva el egreso que la fundación busca eliminar.
- **Solo transcripción manual:** más segura, pero no evalúa la hipótesis técnica de ASR local.

## Consecuencias

- El bucket `context-note-audio`, sus políticas, funciones de acceso, columnas `storage_path`/`audio_duration_ms` y la reproducción en la bitácora se retiran por completo mediante migración aditiva; el hito de texto no se ve afectado.
- El operador delPrototipo pierde la reproducción del audio original de un hito ya publicado: solo conserva el texto que el autor confirmó. Es un coste asumido y explícito.
- La app declara dependencia de ASR nativo y un modelo descargable; el tamaño de aplicación y el tiempo de primer uso crecen.
- La desvinculación del audio del registro elimina el riesgo RK-028 (retención de audio crudo) y con ello la necesidad de gobernarlo.
- La Fondation debe distinguir definitivamente "audio de dictado" (nunca sale del dispositivo) de "nota de hito" (texto confirmado): ya no existe audio de hito almacenado.

## Evidencia y límites

- `supabase/migrations/<timestamp>_context_note_local_transcription.sql`: `transcription_metadata` con constraint de forma y tamaño, retiro de columnas y grants, eliminación del bucket, funciones y políticas de Storage, y `summary` del timeline exponiendo el `content` confirmado.
- `supabase/tests/context_notes_milestones.test.sql`: aceptación del hito de audio con `content` + metadata, rechazo sin `content`, rechazo de metadata en hito de texto, metadata mal formada u sobredimensionada, ausencia de bucket y de políticas de Storage, e idempotencia por `client_event_id`.
- `app/lib/domains/context_note/domain/`: entidad de hito y estados del ciclo de vida local.
- `app/lib/domains/context_note/data/`: `AsrEngine` detrás de interfaz y repositorio sin código de Storage.
- `app/lib/domains/context_note/presentation/`: flujo grabar → transcribir → revisar → confirmar → purgar.
- Manifest `app/assets/asr_model_manifest.json`: origen, licencia, versión y checksum del modelo español; los pesos no se versionan.
- No se afirma calidad clínica de la transcripción, ni comportamiento con datos reales, ni retention productiva: solo demo sintética y local.
