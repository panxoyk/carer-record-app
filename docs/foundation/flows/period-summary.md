# Flujo de resumen de periodo

## Estado y objetivo

**MVP implementado; validación nativa pendiente.** ADR-021 define el resumen histórico persistido. Las pantallas de historial, creación y detalle se abren desde la hospitalización del paciente, sin modal. Código y pruebas automatizadas cubren DB/RLS, dominio, repositorio, controlador, UI y ruta; no se afirma benchmark ni validación manual de privacidad/red en dispositivo.

El resumen es una vista derivada e inmutable, no una nota ni un evento clínico. Se genera localmente con `SynthesisProvider`; fuentes y prompt no salen del dispositivo. El texto generado sí se persiste en Supabase como dato clínico sensible sujeto a RLS.

## Actores y permisos

- Profesional activo con permiso `clinical.summary.use`, permisos de lectura de fuentes y acceso vigente al episodio.
- Administrador de demo con el mismo permiso y los mismos requisitos de acceso propio al episodio; no existe override administrativo.
- Anónimo, suspendido, sin perfil, sin permiso o sin acceso al episodio: denegado.

El permiso único `clinical.summary.use` habilita crear y leer. No habilita lectura de fuentes ni amplía acceso clínico. La concesión inicial es para roles clínicos de demo y administrador; la autoridad final es RLS.

## Selección del periodo y fuentes

Las opciones son 6, 12, 24 o 48 horas, 7 días y rango personalizado de fecha/hora. El valor predeterminado es 24 horas. Se conserva el rango exacto `[from_utc, to_utc)` y la zona IANA institucional. Una fecha seleccionada sin hora incluye el día calendario local completo y se indica claramente como fecha sin hora. Fuentes sin fecha se excluyen y su cantidad se informa.

Solo entran notas confirmadas del episodio y eventos de la timeline FHIR que el actor puede consultar. Filtros opcionales reducen ese conjunto; nunca amplían la autorización. La preparación de fuentes verifica completitud y límites: una fuente truncada, error de consulta o presupuesto excedido impide generar. El MVP asume contexto de modelo de 2048 tokens y preparación conservadora; no incluye chunking.

## Flujo principal

1. Desde el episodio, el usuario abre historial o inicia un resumen nuevo.
2. El historial devuelve únicamente filas autorizadas por `clinical.summary.use` y acceso vigente al episodio.
3. Para nueva generación, el usuario selecciona rango y filtros; se reúnen fuentes permitidas y se informa cualquier limitación y cantidad de fuentes sin fecha.
4. Si las fuentes no están completas o exceden límites, se detiene sin inferencia ni persistencia.
5. `SynthesisProvider` ejecuta inferencia local. La interfaz muestra advertencia sobre la naturaleza asistida y limitaciones disponibles.
6. Se persiste un resumen histórico inmutable con UUID, autor, organización, paciente, hospitalización, rango exacto, zona, fuentes/procedencia, generación y texto.
7. Ante error ambiguo de guardado, retry reusa el mismo UUID y resultado; no ejecuta inferencia otra vez.
8. El detalle presenta el snapshot histórico. Fuentes nuevas no lo invalidan ni fuerzan regeneración; otra generación requiere acción explícita.

La cancelación lógica puede descartar un resultado local antes de persistir. No se promete aborto nativo del motor.

## Exclusiones

- No se edita ni elimina desde la aplicación.
- No hay caché invalidable, regeneración automática ni invalidación por eventos nuevos.
- No hay historia compartida: cada resumen conserva su autor y el acceso al episodio.
- No hay publicación automática, confirmación como nota ni inserción en timeline.
- No se usa proveedor cloud ni se envían fuentes/prompt fuera del dispositivo.

## Datos y RLS

La entidad persistida es tipada y asocia UUID, autor, organización, paciente, hospitalización, límites UTC, zona IANA, filtros/procedencia, texto, advertencia y timestamp de generación. El contrato Flutter para cualquier JSONB consumido es Dart tipado. Grants, constraints y RLS validan tenant, episodio, autoría y `clinical.summary.use`; los identificadores enviados por Flutter no prueban autoridad. No se expone contenido en logs de auditoría.

## Criterios de aceptación

- Historial y detalle solo son alcanzables desde el episodio autorizado y nunca como modal.
- Permiso ausente, revocado, cuenta suspendida, otro tenant o falta de acceso al episodio deniegan creación y lectura, también para administrador.
- Los rangos y fechas locales producen límites UTC exactos, incluyendo DST; fechas sin hora cubren el día local completo y eventos sin fecha se cuentan/excluyen.
- Solo notas confirmadas y timeline FHIR autorizada son entradas; los filtros solo reducen fuentes.
- Respuesta incompleta, truncada, fallida o sobre presupuesto no genera ni persiste.
- Inferencia local, advertencia al generar, snapshot inmutable, UUID estable ante retry de guardado y ninguna inferencia duplicada por retry.
- Eventos posteriores no invalidan ni regeneran; nueva inferencia requiere acción explícita.
- No existe edición, borrado UI, publicación automática ni historia compartida.

## Evidencia y validación pendiente

- pgTAP, pruebas de dominio, repositorio, controlador, UI y ruta cubren los contratos anteriores con datos sintéticos.
- Benchmark y ejecución del modelo nativo en dispositivo siguen pendientes.
- Revisión manual de privacidad/red sigue pendiente. Las pruebas automatizadas verifican payloads/mocks, no ausencia de tráfico real; el texto generado persistido es dato clínico sensible sujeto a RLS.

## Referencias

- [ADR-021](../decisions/adr-021-resumen-periodo-persistido.md) define el MVP vigente.
- [ADR-011](../decisions/adr-011-resumen-temporal-cache.md) conserva antecedentes de intervalo/procedencia; caché e invalidación no rigen el MVP.
- [ADR-017](../decisions/adr-017-sintesis-local.md) define síntesis local.
- [Migración del MVP](../../../supabase/migrations/20261013050000_period_summaries.sql) y [pruebas pgTAP](../../../supabase/tests/period_summaries.test.sql) documentan persistencia/RLS y sus casos automatizados.
- `app/lib/domains/period_summary/` y `app/test/domains/period_summary/` contienen la implementación y pruebas Flutter del corte.
