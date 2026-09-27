# Selección de recursos FHIR R4

## 1. Pregunta de diseño

FHIR R4 ofrece un catálogo amplio y modular. Implementarlo completo no es necesario ni verificable para la demostración de Carer Record. La selección responde a una pregunta más acotada: **¿qué recursos mínimos permiten mostrar una ficha clínica sintética, contextualizada por organización, paciente, atención y ubicación, con condiciones, observaciones, alergias y solicitudes de medicamentos, sin escribir en la FCE?**

La respuesta vinculante es:

- **Dominio seleccionado**: `Organization`, `Patient`, `Encounter`, `Location`, `Condition`, `Observation`, `AllergyIntolerance`, `MedicationRequest`.
- **Infraestructura seleccionada**: `CapabilityStatement`, `Bundle`, `OperationOutcome`.
- **Futuro explícito**: recursos con un caso de uso plausible, pero que requieren nuevas decisiones, dependencias o infraestructura.
- **Descartado para la demo**: recursos sin caso de uso en el alcance o pertenecientes a escritura, workflow, finanzas, investigación, razonamiento, definición o contenido especializado.

“Futuro” no implica compromiso de implementación. “Descartado” se refiere a la demo, no al valor general del recurso ni a una prohibición permanente.

## 2. Evidencia del producto

La selección se apoya en evidencia concreta:

| Evidencia                                                                                                                                      | Interpretación                                                                           |
| ---------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| El baseline registraba consulta clínica de solo lectura (`baseline/carer-record-app.md:9-13`; `supabase/tests/patients_rls.test.sql:133-169`). | Se excluyen workflows de escritura, agenda, órdenes generales y write-back.              |
| El pipeline está intencionalmente diferido (`scripts/data_pipeline/main.py:1-15`).                                                             | La selección es diseño fundacional, no inventario de soporte existente.                  |
| El esquema interno tiene paciente y timeline uniforme (`supabase/migrations/20260910000000_initial_clinical_schema.sql:16-39`).                | Se eligen recursos que aportan contexto o eventos legibles sin replicar el modelo FHIR.  |
| El timeline exige un resumen no vacío (`supabase/migrations/20260910110000_clinical_timeline.sql:45-51`).                                      | Todo mapper clínico debe producir resumen tipado y trazable; raw no se entrega a UI.     |
| La app expone unidad y cama (`app/lib/domains/patient/domain/entities/patient.dart:13-20,51-57`).                                              | `Location` y `Encounter.location` reemplazan inferencias textuales ad hoc.               |
| El seed usa solo datos ficticios (`supabase/seed.sql:22-247`).                                                                                 | La FCE simulada debe mantener datos sintéticos y reproducibles.                          |
| El antecedente importó trece tipos clínicos (`../carer-record/backend/app/fhir/fhir_adapter.py:360-366`).                                      | Demuestra disponibilidad posible, pero no justifica portar todos ni su mapeo.            |
| El antecedente modeló ubicación desde extensiones de `Patient` y `display` (`../carer-record/backend/app/fhir/fhir_adapter.py:182-252`).       | Se selecciona `Location` y se rechaza parsing de texto como contrato.                    |
| El antecedente redujo identificadores y códigos a la primera entrada (`../carer-record/backend/app/fhir/fhir_adapter.py:79-109`).              | La selección exige conservar raw y semántica completa, no solo aumentar número de tipos. |

## 3. Criterios

Cada recurso fue evaluado según:

1. **Necesidad del caso de uso**: contribución directa a la ficha/timeline sintético.
2. **Semántica no sustituible**: riesgo de representar incorrectamente el concepto con otro recurso.
3. **Dependencias**: recursos adicionales, terminología, documentos, binarios, DICOM o workflow necesarios.
4. **Modelo interno**: capacidad de proyectar sin convertir FHIR en el dominio.
5. **Seguridad y privacidad**: sensibilidad y nueva superficie de acceso.
6. **Madurez/interoperabilidad**: estabilidad de R4 y variación esperable entre servidores.
7. **Verificabilidad**: posibilidad de crear fixtures sintéticos y criterios de aceptación reproducibles.
8. **Solo lectura**: compatibilidad con pull incremental y ausencia de write-back.

## 4. Resultado seleccionado

### 4.1 Dominio

| Recurso              | Necesidad                                               | Riesgo controlado                                                            |
| -------------------- | ------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `Organization`       | Atribuye fuente, institución y jerarquía externa.       | No concede tenancy ni permisos; la organización interna se configura.        |
| `Patient`            | Sujeto central de todos los datos.                      | Identidad compuesta y reglas por `Identifier.system`; no fusión automática.  |
| `Encounter`          | Contexto temporal/asistencial y relación con ubicación. | No confundir encounter con ubicación actual permanente.                      |
| `Location`           | Modela sede, unidad, habitación o cama.                 | Jerarquía por referencias/códigos; no parsear `display`.                     |
| `Condition`          | Problemas y diagnósticos relevantes.                    | Respetar estados clínico/verificación e `entered-in-error`.                  |
| `Observation`        | Signos, mediciones y aseveraciones simples.             | Soportar `value[x]`, componentes y ausencia; no reducir todo a string.       |
| `AllergyIntolerance` | Riesgo alérgico/intolerancia relevante para atención.   | No confundir criticidad, severidad y estado; conservar todas las reacciones. |
| `MedicationRequest`  | Prescripción u orden vigente/histórica.                 | No inferir administración, dispensación o adherencia.                        |

### 4.2 Infraestructura

| Recurso               | Necesidad                                 | Límite                                                          |
| --------------------- | ----------------------------------------- | --------------------------------------------------------------- |
| `CapabilityStatement` | Descubrir versión y capacidades reales.   | Snapshot privado; no evento clínico.                            |
| `Bundle`              | Transportar `searchset` y paginación.     | Se procesa por entradas; no implica batch/transaction/document. |
| `OperationOutcome`    | Diagnosticar errores y advertencias FHIR. | Contenido privado y logs redactados.                            |

## 5. Matriz exhaustiva

La matriz cubre todas las entradas concretas del índice categorizado oficial de FHIR R4; `Resource` y `DomainResource` se incluyen primero como bases abstractas para que el análisis no deje implícita su función. Las claves son:

- **S**: seleccionado como recurso de dominio.
- **I**: seleccionado como infraestructura.
- **F**: futuro, condicionado a un caso de uso y diseño adicional.
- **D**: descartado para la demo.
- **A**: base abstracta aplicable, no endpoint seleccionable.

### 5.1 Bases y Foundation

| Recurso                   | Decisión | Argumento                                                                               |
| ------------------------- | -------- | --------------------------------------------------------------------------------------- |
| `Resource`                | A        | Base de `id` y `meta`; sus reglas se implementan transversalmente.                      |
| `DomainResource`          | A        | Base de narrativa, contained y extensiones; no es una instancia autónoma.               |
| `CapabilityStatement`     | I        | Descubrimiento obligatorio de versión, formato, tipos e interacciones.                  |
| `StructureDefinition`     | F        | Necesario para validación formal de perfiles futuros; no se descarga en MVP.            |
| `ImplementationGuide`     | F        | Requerido cuando exista un contrato institucional/nacional acordado.                    |
| `SearchParameter`         | D        | La demo usa parámetros estándar y capacidades declaradas; no ingiere definiciones.      |
| `MessageDefinition`       | D        | No hay mensajería FHIR; solo REST pull.                                                 |
| `OperationDefinition`     | D        | No se invocan operaciones estándar/custom.                                              |
| `CompartmentDefinition`   | F        | Puede informar extracción futura por paciente; no gobierna RLS local.                   |
| `StructureMap`            | F        | Posible lenguaje de transformación futuro; mapper inicial interno/versionado.           |
| `GraphDefinition`         | F        | Útil para expansión futura de grafos; no necesaria para lista cerrada.                  |
| `ExampleScenario`         | D        | Artefacto de documentación, no dato clínico de la demo.                                 |
| `CodeSystem`              | F        | Futuro para validación terminológica gobernada.                                         |
| `ValueSet`                | F        | Futuro para validar bindings de perfiles acordados.                                     |
| `ConceptMap`              | F        | Futuro para equivalencias trazables; no hacer mapping ad hoc en MVP.                    |
| `NamingSystem`            | F        | Futuro para gobernar namespaces de identificadores.                                     |
| `TerminologyCapabilities` | F        | Futuro si se integra un servidor terminológico.                                         |
| `Provenance`              | F        | Puede aportar procedencia emitida por FCE; el linaje interno no lo suplanta ni fabrica. |
| `AuditEvent`              | F        | Necesario en operación real para auditoría; distinto del log técnico.                   |
| `Consent`                 | F        | Requiere modelo legal, políticas y enforcement no definidos.                            |
| `Composition`             | F        | Requiere arquitectura de documentos y `Bundle.type=document`.                           |
| `DocumentManifest`        | F        | Requiere colecciones documentales, inexistentes en MVP.                                 |
| `DocumentReference`       | F        | Prioritario, pero exige Storage, MIME, malware, retención y autorización.               |
| `CatalogEntry`            | D        | No hay caso de catálogos clínicos/comerciales.                                          |
| `Basic`                   | D        | Recurso genérico debilitaría el contrato y ocultaría semántica no soportada.            |
| `Binary`                  | F        | Solo junto con documentos/media y controles de contenido.                               |
| `Bundle`                  | I        | Contenedor de búsqueda y mecanismo de paginación.                                       |
| `Linkage`                 | F        | Posible apoyo a conciliación; no autoriza fusión automática.                            |
| `MessageHeader`           | D        | No se usa mensajería FHIR.                                                              |
| `OperationOutcome`        | I        | Diagnóstico estructurado de errores/advertencias.                                       |
| `Parameters`              | D        | No se ejecutan operaciones que lo requieran.                                            |
| `Subscription`            | F        | Push futuro; polling incremental basta para demo.                                       |

### 5.2 Base

| Recurso                      | Decisión | Argumento                                                                            |
| ---------------------------- | -------- | ------------------------------------------------------------------------------------ |
| `Patient`                    | S        | Sujeto central y vínculo requerido por eventos clínicos.                             |
| `Practitioner`               | F        | Identidad profesional externa no debe fusionarse con Auth interno sin reglas.        |
| `PractitionerRole`           | F        | Requiere practitioner, organización, rol y vigencia.                                 |
| `RelatedPerson`              | F        | Contactos/representantes no son necesarios para timeline inicial.                    |
| `Person`                     | D        | Master person index y resolución intercontexto fuera del MVP.                        |
| `Group`                      | D        | El producto consulta pacientes individuales.                                         |
| `Organization`               | S        | Contextualiza institución/unidad y atribución externa.                               |
| `OrganizationAffiliation`    | F        | Redes interorganizacionales no requeridas en una FCE simulada.                       |
| `HealthcareService`          | F        | Directorio de prestaciones futuro, no hecho clínico.                                 |
| `Endpoint`                   | D        | El endpoint se configura localmente; ingerirlo podría alterar frontera de confianza. |
| `Location`                   | S        | Representación estructurada de unidad/sala/habitación/cama.                          |
| `Substance`                  | F        | Puede resolver alergias/medicamentos referenciados en una fase posterior.            |
| `BiologicallyDerivedProduct` | D        | Trasplante/infusión biológica fuera del caso de uso.                                 |
| `Device`                     | F        | Dispositivos pueden enriquecer observaciones, pero no son requeridos.                |
| `DeviceMetric`               | F        | Depende de integración de dispositivos y semántica de medición.                      |
| `Task`                       | D        | Gestión de trabajo implica workflow y potencial escritura.                           |
| `Appointment`                | D        | Agenda fuera del producto actual.                                                    |
| `AppointmentResponse`        | D        | Depende de agenda y respuestas de participantes.                                     |
| `Schedule`                   | D        | Disponibilidad de agenda fuera del producto actual.                                  |
| `Slot`                       | D        | Reserva de agenda fuera del producto actual.                                         |
| `VerificationResult`         | D        | Verificación de directorios/datos fuera del MVP.                                     |
| `Encounter`                  | S        | Contexto temporal y asistencial de hospitalización/atención.                         |
| `EpisodeOfCare`              | F        | Continuidad longitudinal futura; no necesaria para encuentros demo.                  |
| `Flag`                       | F        | Alertas requieren prioridad, vigencia, gobernanza y UI segura.                       |
| `List`                       | D        | Colección curada no reemplaza recursos fuente ni aporta evento autónomo.             |
| `Library`                    | D        | Activos de conocimiento y lógica fuera del MVP.                                      |

### 5.3 Clinical

| Recurso                      | Decisión | Argumento                                                                         |
| ---------------------------- | -------- | --------------------------------------------------------------------------------- |
| `AllergyIntolerance`         | S        | Riesgo clínico relevante y semántica no sustituible por `Condition`.              |
| `AdverseEvent`               | F        | Evento adverso es distinto de alergia y requiere diseño de seguridad.             |
| `Condition`                  | S        | Problemas/diagnósticos necesarios para ficha y timeline.                          |
| `Procedure`                  | F        | Caso plausible; exige mapper propio, códigos y temporalidad completa.             |
| `FamilyMemberHistory`        | F        | Anamnesis familiar futura, no necesaria para demo.                                |
| `ClinicalImpression`         | F        | Evaluación integrada requiere autoría, evidencia y presentación específicas.      |
| `DetectedIssue`              | F        | Depende de soporte de decisión y gestión de alertas.                              |
| `Observation`                | S        | Mediciones, signos vitales y aseveraciones simples del timeline.                  |
| `Media`                      | D        | Audio/video/foto sensible requiere Storage y controles fuera del alcance.         |
| `DiagnosticReport`           | F        | Prioritario; debe agrupar `Observation`, conclusiones y adjuntos sin duplicación. |
| `Specimen`                   | F        | Relevante al incorporar laboratorio/`DiagnosticReport`.                           |
| `BodyStructure`              | F        | Solo si procedimientos/diagnóstico requieren anatomía detallada.                  |
| `ImagingStudy`               | F        | Requiere DICOM, viewer y seguridad de imágenes.                                   |
| `QuestionnaireResponse`      | F        | Requiere `Questionnaire`, perfiles y presentación de respuestas.                  |
| `MolecularSequence`          | D        | Genómica fuera del alcance y de alta sensibilidad.                                |
| `MedicationRequest`          | S        | Representa prescripción/orden; caso mínimo de medicación.                         |
| `MedicationAdministration`   | F        | Necesario para afirmar administración real; no se infiere de la orden.            |
| `MedicationDispense`         | F        | Flujo de farmacia fuera del MVP.                                                  |
| `MedicationStatement`        | F        | Declaración de consumo requiere distinguir fuente y certeza.                      |
| `Medication`                 | F        | Catálogo/producto futuro; MVP restringe a concepto o contained resoluble.         |
| `MedicationKnowledge`        | D        | Base de conocimiento farmacológico fuera del producto.                            |
| `Immunization`               | F        | Historial vacunal plausible, no necesario para demo.                              |
| `ImmunizationEvaluation`     | D        | Evaluación contra recomendaciones requiere motor especializado.                   |
| `ImmunizationRecommendation` | D        | Forecasting vacunal y soporte de decisión fuera del MVP.                          |
| `CarePlan`                   | F        | Planificación longitudinal futura, con múltiples dependencias.                    |
| `CareTeam`                   | F        | Equipo externo no se deriva de usuarios internos sin conciliación.                |
| `Goal`                       | F        | Depende de plan de cuidado y ciclo de vida propio.                                |
| `ServiceRequest`             | F        | Órdenes no farmacológicas futuras; no necesarias en timeline mínimo.              |
| `NutritionOrder`             | F        | Orden nutricional futura si el caso asistencial lo exige.                         |
| `VisionPrescription`         | D        | Especialidad fuera del alcance.                                                   |
| `RiskAssessment`             | F        | Requiere gobernanza de modelos, probabilidad y comunicación de riesgo.            |
| `RequestGroup`               | F        | Solo con órdenes/planes complejos y dependencias.                                 |
| `Communication`              | F        | Comunicación clínica futura; no equivale automáticamente a nota local.            |
| `CommunicationRequest`       | D        | Solicitud de comunicación y workflow fuera del MVP.                               |
| `DeviceRequest`              | F        | Depende de soporte de dispositivos y órdenes.                                     |
| `DeviceUseStatement`         | F        | Depende de soporte de dispositivos y procedencia de declaración.                  |
| `GuidanceResponse`           | D        | Respuesta de CDS fuera del MVP.                                                   |
| `SupplyRequest`              | D        | Solicitud logística fuera del MVP.                                                |
| `SupplyDelivery`             | D        | Entrega logística fuera del MVP.                                                  |

### 5.4 Financial

| Recurso                       | Decisión | Argumento                                                          |
| ----------------------------- | -------- | ------------------------------------------------------------------ |
| `Coverage`                    | D        | Cobertura/seguro fuera del caso de uso clínico de turno.           |
| `CoverageEligibilityRequest`  | D        | Solicitud financiera y de intercambio bidireccional fuera del MVP. |
| `CoverageEligibilityResponse` | D        | Respuesta de elegibilidad sin consumidor en el producto.           |
| `EnrollmentRequest`           | D        | Inscripción de seguro fuera del MVP.                               |
| `EnrollmentResponse`          | D        | Respuesta de inscripción fuera del MVP.                            |
| `Claim`                       | D        | Reclamación/facturación fuera del MVP.                             |
| `ClaimResponse`               | D        | Adjudicación de reclamación fuera del MVP.                         |
| `Invoice`                     | D        | Facturación fuera del MVP.                                         |
| `PaymentNotice`               | D        | Aviso de pago fuera del MVP.                                       |
| `PaymentReconciliation`       | D        | Conciliación de pagos fuera del MVP.                               |
| `Account`                     | D        | Cuenta financiera/costos fuera del MVP.                            |
| `ChargeItem`                  | D        | Cargo facturable fuera del MVP.                                    |
| `ChargeItemDefinition`        | D        | Definición de precios/cargos fuera del MVP.                        |
| `Contract`                    | D        | Contrato legal/financiero fuera del MVP.                           |
| `ExplanationOfBenefit`        | D        | Explicación de beneficios fuera del MVP.                           |
| `InsurancePlan`               | D        | Catálogo de planes de seguro fuera del MVP.                        |

### 5.5 Specialized

| Recurso                             | Decisión | Argumento                                                                    |
| ----------------------------------- | -------- | ---------------------------------------------------------------------------- |
| `ResearchStudy`                     | D        | Investigación requiere propósito, ética y permisos ajenos a la demo.         |
| `ResearchSubject`                   | D        | Participación en estudios fuera del producto.                                |
| `ActivityDefinition`                | F        | Definición reutilizable futura para planes/CDS; no hecho clínico.            |
| `DeviceDefinition`                  | F        | Futuro junto con catálogo de dispositivos.                                   |
| `EventDefinition`                   | D        | Definición de eventos para razonamiento fuera del MVP.                       |
| `ObservationDefinition`             | F        | Puede apoyar catálogos de laboratorio; no necesaria para observaciones demo. |
| `PlanDefinition`                    | F        | Futuro para protocolos/CDS, con gobernanza propia.                           |
| `Questionnaire`                     | F        | Futuro junto con `QuestionnaireResponse`.                                    |
| `SpecimenDefinition`                | F        | Futuro junto con laboratorio y `Specimen`.                                   |
| `ResearchDefinition`                | D        | Definición PICO/evidencia fuera del producto.                                |
| `ResearchElementDefinition`         | D        | Elementos de investigación fuera del producto.                               |
| `Evidence`                          | D        | Repositorio de evidencia fuera del producto.                                 |
| `EvidenceVariable`                  | D        | Variable PICO fuera del producto.                                            |
| `EffectEvidenceSynthesis`           | D        | Síntesis de efectos fuera del producto.                                      |
| `RiskEvidenceSynthesis`             | D        | Síntesis de riesgos poblacionales fuera del producto.                        |
| `Measure`                           | F        | Analítica/calidad futura, no atención individual demo.                       |
| `MeasureReport`                     | F        | Reporte de calidad futuro, depende de `Measure`.                             |
| `TestScript`                        | D        | Artefacto de prueba de conformidad, no dato a ingerir.                       |
| `TestReport`                        | D        | Resultado de prueba de conformidad, no dato clínico.                         |
| `MedicinalProduct`                  | D        | Dossier regulatorio, no solicitud clínica.                                   |
| `MedicinalProductAuthorization`     | D        | Autorización regulatoria fuera del MVP.                                      |
| `MedicinalProductContraindication`  | D        | Definición regulatoria; no reemplaza alerta individual.                      |
| `MedicinalProductIndication`        | D        | Indicación regulatoria fuera del MVP.                                        |
| `MedicinalProductIngredient`        | D        | Composición regulatoria fuera del MVP.                                       |
| `MedicinalProductInteraction`       | D        | Interacción regulatoria/CDS fuera del MVP.                                   |
| `MedicinalProductManufactured`      | D        | Producto manufacturado regulatorio fuera del MVP.                            |
| `MedicinalProductPackaged`          | D        | Empaque regulatorio fuera del MVP.                                           |
| `MedicinalProductPharmaceutical`    | D        | Forma farmacéutica regulatoria fuera del MVP.                                |
| `MedicinalProductUndesirableEffect` | D        | Efectos regulatorios fuera del MVP.                                          |
| `SubstanceNucleicAcid`              | D        | Definición especializada/genómica fuera del MVP.                             |
| `SubstancePolymer`                  | D        | Definición especializada de polímeros fuera del MVP.                         |
| `SubstanceProtein`                  | D        | Definición especializada de proteínas fuera del MVP.                         |
| `SubstanceReferenceInformation`     | D        | Información regulatoria de sustancia fuera del MVP.                          |
| `SubstanceSpecification`            | D        | Especificación detallada de sustancia fuera del MVP.                         |
| `SubstanceSourceMaterial`           | D        | Origen taxonómico/material fuera del MVP.                                    |

## 6. Por qué no se selecciona lo que el antecedente importaba

`../carer-record` declara `Procedure`, `Immunization`, `DiagnosticReport`, `ImagingStudy`, `CarePlan`, `CareTeam` y `Device`, además del subconjunto actual (`../carer-record/backend/app/fhir/fhir_adapter.py:360-366`). Esa amplitud no demuestra soporte interoperable:

- cada recurso se reduce a columnas parciales y se pierde el JSON original (`../carer-record/backend/app/fhir/fhir_adapter.py:390-823`);
- la identidad de sincronización solo considera tipo e ID (`../carer-record/backend/app/core/init_db.sql:114-126`);
- no se conserva `meta.versionId` ni `meta.lastUpdated`;
- no se descubre `CapabilityStatement`;
- el importador afirma ser “completo” (`../carer-record/backend/app/fhir/fhir_adapter.py:1-5`), pero no valida perfiles, referencias o variantes exhaustivas;
- el sincronizador incrementa el conteo incluso cuando `_upsert_clinical` absorbió un error (`../carer-record/backend/app/sync/sync_service.py:255-272,375-413`).

La selección nueva privilegia profundidad verificable sobre número de nombres reconocidos. Un recurso se considera soportado solo cuando existen identidad, versionado, raw, procedencia, referencias, mapeo, errores y pruebas sintéticas de sus variantes acordadas.

## 7. Decisiones específicas de frontera

### 7.1 DiagnosticReport y Observation

La especificación ubica resultados atómicos en `Observation` y paneles/informes en `DiagnosticReport`. El MVP selecciona `Observation` porque soporta signos vitales y resultados simples sin exigir una capa documental. `DiagnosticReport` se incorpora después de definir:

- vínculo y deduplicación de `DiagnosticReport.result`;
- agrupación de observaciones en UI;
- `effective[x]` frente a `issued`;
- conclusiones codificadas/textuales;
- `presentedForm`, imágenes y specimens;
- autorización de adjuntos.

Referencia oficial: [Guide to Resources: Clinical Findings](https://hl7.org/fhir/R4/resourceguide.html) y [DiagnosticReport](https://hl7.org/fhir/R4/diagnosticreport.html).

### 7.2 DocumentReference

El evento interno `document` no basta para soportar `DocumentReference`. Este recurso puede apuntar a contenido por URL o attachment y requiere resolver disponibilidad, tipo MIME, hash, tamaño, custodia, autoría, contexto y seguridad. Antes de seleccionarlo deben existir Storage privado, escaneo, límites, expiración de URLs, retención y RLS específicas.

Referencia oficial: [DocumentReference](https://hl7.org/fhir/R4/documentreference.html).

### 7.3 MedicationRequest sin Medication completo

FHIR R4 permite `medicationCodeableConcept` o `medicationReference`. La demo selecciona el primero y admite un `Medication` contenido resoluble; no declara soporte general de catálogos `Medication`. Una referencia externa no resuelta queda pendiente/cuarentenada y el raw se conserva. Esto evita presentar una orden sin poder identificar el medicamento.

Referencia oficial: [MedicationRequest](https://hl7.org/fhir/R4/medicationrequest.html).

### 7.4 Procedencia

El pipeline registra procedencia interna obligatoria de toda ingesta. Eso no convierte `Provenance` en seleccionado: una instancia FHIR `Provenance` contiene afirmaciones del emisor sobre actividad, agentes y entidades. Carer Record no debe generar esas afirmaciones en nombre de la FCE. Se evaluará su lectura cuando la fuente simulada o real lo provea con referencias versionadas.

Referencia oficial: [Provenance](https://hl7.org/fhir/R4/provenance.html).

## 8. Condiciones para ampliar la selección

Un recurso futuro pasa a seleccionado únicamente si existe:

1. caso de uso y usuario consumidor documentados;
2. perfil R4 o contrato de fuente con variantes admitidas;
3. estrategia de identidad, referencias y versionado;
4. mapeo al modelo interno sin falsificar semántica;
5. política de datos raw, retención, RLS y logs;
6. tratamiento de `OperationOutcome` y cuarentena;
7. fixtures exclusivamente sintéticos, incluidos cambios y errores;
8. pruebas de idempotencia, paginación, checkpoint y reproceso;
9. actualización de esta matriz y del catálogo;
10. confirmación de que no introduce write-back implícito.

## 9. Fuentes oficiales por decisión

- [Índice categorizado de recursos R4](https://hl7.org/fhir/R4/resourcelist.html)
- [Guía de intención y selección de recursos](https://hl7.org/fhir/R4/resourceguide.html)
- [API REST y CapabilityStatement](https://hl7.org/fhir/R4/http.html)
- [Búsqueda y paginación](https://hl7.org/fhir/R4/search.html)
- [Metadatos y versionado de Resource](https://hl7.org/fhir/R4/resource.html#metadata)
- [Organization](https://hl7.org/fhir/R4/organization.html)
- [Patient](https://hl7.org/fhir/R4/patient.html)
- [Encounter](https://hl7.org/fhir/R4/encounter.html)
- [Location](https://hl7.org/fhir/R4/location.html)
- [Condition](https://hl7.org/fhir/R4/condition.html)
- [Observation](https://hl7.org/fhir/R4/observation.html)
- [AllergyIntolerance](https://hl7.org/fhir/R4/allergyintolerance.html)
- [MedicationRequest](https://hl7.org/fhir/R4/medicationrequest.html)
- [Bundle](https://hl7.org/fhir/R4/bundle.html)
- [OperationOutcome](https://hl7.org/fhir/R4/operationoutcome.html)
