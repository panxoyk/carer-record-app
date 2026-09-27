# Visión de producto

## Propósito del documento

Este documento fija la visión de Carer Record y separa deliberadamente el producto deseado, el alcance académico y las capacidades observadas en el baseline histórico. Esas afirmaciones se respaldan con evidencia mediante referencias `ruta:línea`, relativas a la raíz de `carer-record-app`; las referencias que comienzan con `../carer-record/` pertenecen al repositorio hermano. Para conocer la implementación posterior se verifican directamente código, migraciones y pruebas.

## Convención de estado

| Estado               | Significado                                                                                        |
| -------------------- | -------------------------------------------------------------------------------------------------- |
| **Confirmado**       | Existe evidencia verificable en documentación, código, migraciones o pruebas.                      |
| **Decidido**         | Define la dirección que estos documentos adoptan aunque todavía no esté implementada por completo. |
| **Propuesto**        | Hipótesis o siguiente paso sujeto a diseño, priorización o validación.                             |
| **Pendiente**        | Falta implementación, evidencia reproducible o una decisión explícita.                             |
| **Fuera de alcance** | No forma parte de la etapa académica o del incremento actual.                                      |

## Enunciado de visión

**Decidido.** Carer Record es una capa de contexto clínico para hospitalización. Su propósito es reunir, ordenar y presentar información relevante que se encuentra distribuida entre sistemas y registros, de modo que el personal autorizado pueda comprender con rapidez el estado y la evolución de un paciente, especialmente durante los cambios de turno.

No es una Ficha Clínica Electrónica (FCE), no pretende sustituir las fuentes oficiales y no debe transformarse en un repositorio paralelo sin trazabilidad. Su función es complementar los sistemas existentes, conservar la relación con la fuente y reducir el trabajo necesario para reconstruir el contexto de un caso. Esta definición coincide con la descripción, diferenciación y posicionamiento originales (`../carer-record/carer-record.md:5`, `../carer-record/carer-record.md:9`, `../carer-record/carer-record.md:153`, `../carer-record/carer-record.md:209`).

## Problema que aborda

**Confirmado.** La hipótesis de problema del proyecto es que la información útil durante una hospitalización puede existir, pero estar fragmentada entre ficha clínica, exámenes, tratamientos, notas, registros administrativos y comunicaciones informales. En un cambio de turno, el equipo entrante debe reconstruir en poco tiempo qué ocurrió, qué cambió y qué requiere atención (`../carer-record/carer-record.md:13`, `../carer-record/carer-record.md:15`).

**Confirmado.** Parte del contexto cotidiano puede quedar fuera de los registros estructurados y perder trazabilidad cuando se comunica verbalmente, en papel o por canales informales (`../carer-record/carer-record.md:17`). El trabajo académico formula esta situación como un vacío entre lo que está registrado y lo que el equipo alcanza a comprender y comunicar durante el traspaso (`../carer-record/informe/Indice/Introduccion/problema-a-resolver.tex:3`).

**Pendiente.** La magnitud del problema, su frecuencia, los tiempos reales de contextualización y el valor clínico de la solución no están validados con usuarios. El repositorio hermano declara que todavía no existen participantes, observaciones, tiempos de tarea ni resultados SUS (`../carer-record/informe/Indice/Verificacion y Validacion/validacion-del-prototipo.tex:3`).

## Propuesta de valor

**Decidido.** La propuesta de valor es transformar información clínica fragmentada en contexto hospitalario útil, trazable y de baja carga cognitiva. El producto debe permitir que una persona autorizada:

- identifique al paciente y su ubicación hospitalaria;
- consulte eventos relevantes en una secuencia temporal comprensible;
- distinga información reciente sin recorrer múltiples módulos;
- conozca la fuente, fecha y autoría cuando esos datos existan;
- profundice en el antecedente original en vez de aceptar una síntesis opaca;
- registre, en una etapa posterior y con permisos explícitos, contexto complementario que no sustituya el registro formal.

La visión original prioriza una vista única, cronológica y contextualizada, no la acumulación indiscriminada de datos (`../carer-record/carer-record.md:23`, `../carer-record/carer-record.md:25`, `../carer-record/carer-record.md:94`).

## Lugar dentro del ecosistema hospitalario

| Sistema o actor               | Responsabilidad                                              | Relación con Carer Record                                                       | Estado                                        |
| ----------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------------- | --------------------------------------------- |
| FCE, SIH y sistemas de origen | Mantener los registros clínicos y administrativos oficiales. | Son fuentes autoritativas; Carer Record no las reemplaza.                       | **Decidido**                                  |
| Carer Record                  | Integrar y presentar contexto útil para hospitalización.     | Capa complementaria de consulta y, en el futuro, captura contextual controlada. | **Decidido**                                  |
| Personal clínico autorizado   | Interpretar la información y tomar decisiones asistenciales. | Usuario directo y responsable del juicio clínico.                               | **Decidido**                                  |
| Institución de salud          | Autorizar fuentes, accesos, despliegue y reglas de uso.      | Cliente y responsable de habilitar la integración institucional.                | **Propuesto**                                 |
| Paciente                      | Recibir atención coordinada.                                 | Beneficiario indirecto; no es usuario directo en esta etapa.                    | **Fuera de alcance** para interacción directa |
| IA                            | Organizar, transcribir o resumir bajo revisión humana.       | Herramienta de apoyo; nunca autoridad clínica.                                  | **Futuro / Pendiente**                        |

El baseline de CRA ya materializaba una porción acotada de esta visión: listaba pacientes y eventos para roles asistenciales activos en modo de solo lectura (`supabase/tests/patients_rls.test.sql:56-130`). No integraba fuentes hospitalarias ni registraba contexto nuevo; su pipeline FHIR era únicamente un scaffold que declaraba la ingesta diferida (`scripts/data_pipeline/main.py:2`, `scripts/data_pipeline/main.py:14`).

## Usuarios y necesidades

### Personal clínico

**Decidido.** Los usuarios directos son médicos, profesionales de enfermería, técnicos y otros integrantes autorizados del equipo asistencial. Necesitan una interfaz rápida, clara y compatible con un entorno de alta presión, sin pasos administrativos que no aporten al cuidado (`../carer-record/carer-record.md:54`, `../carer-record/carer-record.md:58`).

**Confirmado en el baseline.** Las políticas capturadas reconocen `physician`, `nurse` y `technician` como roles clínicos con acceso de lectura; `administrator` gestiona practitioners y no recibe acceso clínico implícito (`supabase/tests/patients_rls.test.sql:56-116`).

### Administración institucional

**Decidido.** La administración configura identidades y estados de cuenta, pero la autoridad administrativa no equivale a autoridad clínica. CRA implementa esta separación tanto en navegación como en RLS (`app/lib/core/router/app_router.dart:35`, `app/lib/core/router/app_router.dart:41`, `supabase/migrations/20260910100000_patient_read_access.sql:10`).

### Pacientes

**Decidido.** Los pacientes son beneficiarios indirectos de una mejor continuidad informativa. No se plantea acceso del paciente, mensajería con familiares ni comunicación externa durante el alcance académico actual (`../carer-record/carer-record.md:66`, `../carer-record/carer-record.md:195`).

## Principios del producto

### Complementar, no reemplazar

**Decidido.** Toda capacidad debe preservar la diferencia entre contexto de apoyo y registro clínico oficial. Una síntesis o nota de Carer Record no adquiere por sí sola el carácter de fuente primaria (`../carer-record/carer-record.md:155`, `../carer-record/carer-record.md:164`).

### Fuente y trazabilidad antes que síntesis

**Decidido.** La información presentada debe mantener, cuando corresponda, procedencia, fecha y autoría. Si una futura síntesis no puede vincularse con sus antecedentes, no cumple la visión de confianza del producto (`../carer-record/carer-record.md:109`, `../carer-record/carer-record.md:111`).

### Mínimo privilegio

**Decidido.** La autorización efectiva reside en el servidor y no en la interfaz. CRA adopta RLS como autoridad, restringe el acceso clínico mediante permisos explícitos y separa la creación privilegiada de usuarios en una Edge Function (`AGENTS.md:13-18`, `supabase/functions/create-practitioner/index.ts:38`).

### Datos sintéticos durante la etapa académica

**Decidido.** El desarrollo, las demostraciones y las pruebas utilizan exclusivamente datos sintéticos. CRA prohíbe datos clínicos reales en base local, dispositivos, logs y exportaciones de desarrollo (ADR-002; [`10-security-privacy.md`](10-security-privacy.md)).

### IA bajo revisión humana

**Decidido.** La IA, si se incorpora, puede transcribir, organizar, clasificar o proponer borradores, pero no diagnosticar, prescribir, completar hechos ausentes ni tomar decisiones autónomas. Toda salida debe ser revisable y conservar relación con sus fuentes (`../carer-record/carer-record.md:98`, `../carer-record/carer-record.md:109`).

### Implementación gradual

**Decidido.** La solución debe comenzar con una unidad, fuentes y flujos acotados, y ampliar cobertura solo después de producir evidencia de utilidad, seguridad y adopción (`../carer-record/carer-record.md:189`). Los cortes verticales y sus gates se definen en [`12-delivery-roadmap.md`](12-delivery-roadmap.md).

## Resultado esperado

**Propuesto.** El éxito del producto se evaluará por resultados observables, no por cantidad de pantallas o datos:

- menor tiempo para comprender un caso al inicio de un turno;
- menor navegación entre fuentes para responder preguntas de contexto;
- trazabilidad suficiente para identificar origen, momento y autoría;
- ausencia de accesos no autorizados en los escenarios definidos;
- capacidad del usuario para distinguir datos fuente, contexto agregado y contenido generado;
- utilidad percibida y carga de uso medidas con un protocolo reproducible.

**Pendiente.** No existen todavía línea base, umbrales de aceptación ni resultados con personal clínico. El protocolo académico propone medir completitud, tiempo, errores y SUS, pero aún debe ejecutarse (`../carer-record/informe/Indice/Verificacion y Validacion/validacion-del-prototipo.tex:14`).

## Límites de la visión

**Fuera de alcance.** Carer Record no es:

- una FCE sustituta ni el origen oficial de toda información clínica;
- una herramienta de diagnóstico, prescripción o decisión clínica autónoma;
- un canal directo con familiares;
- una certificación de interoperabilidad con un hospital real;
- una autorización para usar datos reales en el prototipo académico;
- una promesa de operación productiva, cumplimiento normativo o disponibilidad clínica.

Estos límites están alineados con el posicionamiento original (`../carer-record/carer-record.md:193`, `../carer-record/carer-record.md:211`) y con la falta de validación clínica del prototipo (`../carer-record/informe/Indice/Verificacion y Validacion/validacion-del-prototipo.tex:18`).

## Decisión de continuidad

**Decidido.** La visión se continuará implementando en `carer-record-app` (CRA). El repositorio hermano conserva evidencia conceptual y capacidades experimentales valiosas, pero CRA ofrece una base más acotada y verificable para autorización, datos sintéticos y evolución incremental. La comparación y la justificación fechadas se registran en [`baseline/comparison.md`](baseline/comparison.md).
