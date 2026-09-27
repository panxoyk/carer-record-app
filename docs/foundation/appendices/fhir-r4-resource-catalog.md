# Catálogo de recursos FHIR R4

## 1. Alcance del catálogo

Este apéndice presenta el universo de recursos de **FHIR R4 v4.0.1** por las familias funcionales de la lista oficial de HL7. Su propósito es delimitar el estándar antes de seleccionar el subconjunto de Carer Record. Una aparición en este catálogo **no significa que el recurso esté implementado, ingerido, persistido o mostrado**.

La clasificación oficial es informativa y un recurso puede participar en más de un proceso clínico. Por ejemplo, `Observation` aparece en diagnósticos, pero también representa signos vitales y antecedentes sociales; `Bundle` es infraestructura de transporte y puede contener cualquier familia. La semántica normativa reside en la página de cada recurso, no en el resumen de este documento.

Fuentes oficiales:

- [Índice de recursos FHIR R4](https://hl7.org/fhir/R4/resourcelist.html)
- [Guía de recursos FHIR R4](https://hl7.org/fhir/R4/resourceguide.html)
- [CodeSystem `resource-types` de R4](https://hl7.org/fhir/R4/codesystem-resource-types.html)
- [Módulos de FHIR R4](https://hl7.org/fhir/R4/modules.html)
- [Estados normativos y madurez FMM](https://hl7.org/fhir/R4/versions.html)

La decisión individual para cada recurso está en [Selección de recursos FHIR](fhir-resource-selection.md). La arquitectura selecciona ocho recursos de dominio y tres de infraestructura; todos los demás quedan futuros o descartados para la demostración.

## 2. Bases abstractas

`Resource` es la raíz abstracta de todos los recursos e incorpora `id`, `meta`, `implicitRules` y `language`. `DomainResource` añade narrativa, recursos contenidos y extensiones. No son endpoints de ingesta ni instancias clínicas autónomas, pero sus reglas se aplican a los recursos derivados.

Elementos transversales relevantes:

| Elemento                           | Uso en la integración                                                                                                                                 |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Resource.id`                      | Forma `external_id` dentro de la identidad compuesta local. Es lógico y relativo al servidor/tipo.                                                    |
| `Resource.meta.versionId`          | Versión opaca de la fuente; se preserva sin interpretar su orden.                                                                                     |
| `Resource.meta.lastUpdated`        | Instante de última actualización declarado por la fuente; alimenta sincronización incremental.                                                        |
| `Resource.meta.profile`            | Perfiles que el emisor afirma cumplir; condicionan validación y mapeo.                                                                                |
| `DomainResource.contained`         | Recursos sin existencia independiente fuera del contenedor; requieren identidad local subordinada.                                                    |
| `DomainResource.extension`         | Datos adicionales gobernados por URL; no se interpretan por coincidencias de texto.                                                                   |
| `DomainResource.modifierExtension` | Puede cambiar la interpretación; una extensión modificadora desconocida impide una proyección segura.                                                 |
| `DomainResource.text`              | Narrativa clínicamente segura según el emisor, pero no sustituto automático de elementos estructurados ni contenido para renderizar sin sanitización. |

Referencias: [Resource](https://hl7.org/fhir/R4/resource.html), [DomainResource](https://hl7.org/fhir/R4/domainresource.html), [Extensibilidad](https://hl7.org/fhir/R4/extensibility.html) y [Referencias](https://hl7.org/fhir/R4/references.html).

## 3. Foundation

La familia Foundation define contratos computables, terminología, seguridad, documentos e infraestructura común. La mayor parte no representa hechos clínicos de un paciente.

### 3.1 Conformance

| Recurso                 | Finalidad normativa resumida                                                                        | Tratamiento en Carer Record                                       |
| ----------------------- | --------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| `CapabilityStatement`   | Declara versión, formatos, recursos, interacciones, búsquedas y operaciones ofrecidas o requeridas. | **Infraestructura MVP** para descubrimiento y validación.         |
| `StructureDefinition`   | Define recursos, tipos, perfiles, extensiones y restricciones.                                      | Futuro para validación formal de perfiles acordados.              |
| `ImplementationGuide`   | Agrupa reglas y artefactos para resolver un problema de interoperabilidad.                          | Futuro cuando exista un contrato institucional/país.              |
| `SearchParameter`       | Define parámetros de búsqueda computables.                                                          | No ingerido; se usan parámetros estándar anunciados.              |
| `MessageDefinition`     | Define eventos y contenido de mensajería FHIR.                                                      | Descartado: la demo usa REST pull, no messaging.                  |
| `OperationDefinition`   | Define operaciones FHIR y consultas nombradas.                                                      | Descartado: no se invocan operaciones custom.                     |
| `CompartmentDefinition` | Define pertenencia de recursos a compartimentos.                                                    | Futuro para análisis de alcance, no para autorización local.      |
| `StructureMap`          | Declara transformaciones entre estructuras.                                                         | Futuro; los mappers iniciales son internos y versionados.         |
| `GraphDefinition`       | Define grafos de recursos por referencias.                                                          | Futuro para expansión controlada de dependencias.                 |
| `ExampleScenario`       | Documenta instancias y pasos de un workflow.                                                        | Descartado como dato de producción; útil solo para documentación. |

### 3.2 Terminology

| Recurso                   | Finalidad normativa resumida                                  | Tratamiento en Carer Record                                  |
| ------------------------- | ------------------------------------------------------------- | ------------------------------------------------------------ |
| `CodeSystem`              | Declara un sistema de códigos y, opcionalmente, su contenido. | Futuro: terminología gobernada, no catálogo clínico del MVP. |
| `ValueSet`                | Define conjuntos de códigos para un contexto.                 | Futuro para validar bindings de perfiles.                    |
| `ConceptMap`              | Expresa relaciones entre conceptos o estructuras.             | Futuro para equivalencias terminológicas auditables.         |
| `NamingSystem`            | Registra namespaces que emiten identificadores o códigos.     | Futuro para gobierno de `Identifier.system`.                 |
| `TerminologyCapabilities` | Declara capacidades de un servidor terminológico.             | Futuro; la demo no integra terminología remota.              |

### 3.3 Security

| Recurso      | Finalidad normativa resumida                                                      | Tratamiento en Carer Record                                          |
| ------------ | --------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| `Provenance` | Describe agentes, actividades y entidades que produjeron o influyeron un recurso. | Futuro. El MVP registra linaje interno, sin fabricar `Provenance`.   |
| `AuditEvent` | Registra eventos de seguridad y uso para auditoría.                               | Futuro para operación real; no reemplaza logs privados del pipeline. |
| `Consent`    | Representa permisos o denegaciones del titular bajo una política.                 | Futuro sujeto a modelo legal y asistencial.                          |

### 3.4 Documents

| Recurso             | Finalidad normativa resumida                                                              | Tratamiento en Carer Record                                            |
| ------------------- | ----------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `Composition`       | Organiza un documento clínico con contexto y atestación; requiere `Bundle.type=document`. | Futuro junto con arquitectura documental.                              |
| `DocumentManifest`  | Agrupa documentos y metadatos comunes.                                                    | Futuro; no hay colección documental en la demo.                        |
| `DocumentReference` | Describe y permite descubrir un documento o adjunto.                                      | **Futuro prioritario**; requiere Storage, MIME, seguridad y retención. |
| `CatalogEntry`      | Contextualiza elementos incluidos en un catálogo.                                         | Descartado: no existe caso de catálogo.                                |

### 3.5 Other infrastructure

| Recurso            | Finalidad normativa resumida                                           | Tratamiento en Carer Record                                 |
| ------------------ | ---------------------------------------------------------------------- | ----------------------------------------------------------- |
| `Basic`            | Permite conceptos sin recurso específico.                              | Descartado: debilitaría el contrato tipado.                 |
| `Binary`           | Representa contenido binario en formato nativo.                        | Futuro con documentos; no se descargan adjuntos en la demo. |
| `Bundle`           | Contiene colecciones, búsquedas, documentos, mensajes o transacciones. | **Infraestructura MVP** para `searchset` y paginación.      |
| `Linkage`          | Vincula registros que representan la misma ocurrencia real.            | Futuro para conciliación, no fusión automática.             |
| `MessageHeader`    | Encabeza un intercambio de mensajería FHIR.                            | Descartado: no se usa messaging.                            |
| `OperationOutcome` | Comunica errores, advertencias e información de una acción.            | **Infraestructura MVP** para diagnóstico.                   |
| `Parameters`       | Transporta parámetros de operaciones; no tiene endpoint REST propio.   | Descartado: no se invocan operaciones.                      |
| `Subscription`     | Configura notificaciones push por cambios.                             | Futuro; la demo usa polling incremental.                    |

## 4. Base

La familia Base describe personas, organizaciones, lugares, dispositivos, agenda, workflow y contexto administrativo de la atención.

### 4.1 Individuals

| Recurso            | Finalidad normativa resumida                                            | Tratamiento en Carer Record                               |
| ------------------ | ----------------------------------------------------------------------- | --------------------------------------------------------- |
| `Patient`          | Demografía e información administrativa del sujeto que recibe atención. | **Seleccionado MVP**.                                     |
| `Practitioner`     | Persona que participa directa o indirectamente en atención.             | Futuro; no se fusiona con usuario autenticado interno.    |
| `PractitionerRole` | Rol, organización, especialidad, servicio y período de un profesional.  | Futuro junto con `Practitioner`.                          |
| `RelatedPerson`    | Persona vinculada al paciente sin responsabilidad profesional formal.   | Futuro si el producto incorpora contactos/representantes. |
| `Person`           | Identidad administrativa independiente de un contexto sanitario.        | Descartado: resolución maestra de personas fuera del MVP. |
| `Group`            | Colección de entidades tratada colectivamente.                          | Descartado: el timeline es individual.                    |

### 4.2 Entities 1

| Recurso                   | Finalidad normativa resumida                                         | Tratamiento en Carer Record                                       |
| ------------------------- | -------------------------------------------------------------------- | ----------------------------------------------------------------- |
| `Organization`            | Agrupación reconocida, incluidas instituciones y unidades.           | **Seleccionado MVP** para contexto de fuente.                     |
| `OrganizationAffiliation` | Relación entre organizaciones distinta de `partOf`.                  | Futuro para redes asistenciales.                                  |
| `HealthcareService`       | Servicio asistencial disponible en una ubicación.                    | Futuro para directorio; no necesario en el timeline.              |
| `Endpoint`                | Detalles técnicos de un endpoint electrónico.                        | Descartado como dato ingerido; la fuente se configura localmente. |
| `Location`                | Lugar físico o virtual donde se prestan servicios o ubican recursos. | **Seleccionado MVP** para jerarquía unidad/sala/cama.             |

### 4.3 Entities 2

| Recurso                      | Finalidad normativa resumida                               | Tratamiento en Carer Record                                   |
| ---------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------- |
| `Substance`                  | Material homogéneo con composición definida.               | Futuro si alergias/medicación requieren referencias externas. |
| `BiologicallyDerivedProduct` | Producto biológico destinado a trasplante o infusión.      | Descartado por ausencia de caso de uso.                       |
| `Device`                     | Artículo manufacturado usado en atención.                  | Futuro para dispositivos clínicos.                            |
| `DeviceMetric`               | Capacidad de medición, cálculo o ajuste de un dispositivo. | Futuro junto con integración de dispositivos.                 |

### 4.4 Workflow

| Recurso               | Finalidad normativa resumida                    | Tratamiento en Carer Record                          |
| --------------------- | ----------------------------------------------- | ---------------------------------------------------- |
| `Task`                | Trabajo que debe realizarse y su ciclo de vida. | Descartado: implicaría workflow operativo/escritura. |
| `Appointment`         | Reserva de un evento asistencial.               | Descartado: agenda fuera del MVP.                    |
| `AppointmentResponse` | Respuesta de un participante a una cita.        | Descartado: agenda fuera del MVP.                    |
| `Schedule`            | Contenedor de períodos disponibles para agenda. | Descartado: agenda fuera del MVP.                    |
| `Slot`                | Intervalo de agenda potencialmente reservable.  | Descartado: agenda fuera del MVP.                    |
| `VerificationResult`  | Estado y evidencia de validación de elementos.  | Descartado: directorios/verificación fuera del MVP.  |

### 4.5 Management

| Recurso         | Finalidad normativa resumida                                                      | Tratamiento en Carer Record                             |
| --------------- | --------------------------------------------------------------------------------- | ------------------------------------------------------- |
| `Encounter`     | Interacción entre paciente y prestadores para atención o evaluación.              | **Seleccionado MVP**.                                   |
| `EpisodeOfCare` | Relación longitudinal paciente-organización dentro de la cual ocurren encuentros. | Futuro para continuidad asistencial más amplia.         |
| `Flag`          | Advertencia prospectiva relevante para la atención.                               | Futuro tras reglas de prioridad, vigencia y seguridad.  |
| `List`          | Colección curada de recursos.                                                     | Descartado: no es el origen de verdad de cada elemento. |
| `Library`       | Contenedor de activos de conocimiento.                                            | Descartado: razonamiento clínico fuera del MVP.         |

## 5. Clinical

La familia Clinical representa hechos, evaluaciones, resultados, medicación, planificación y solicitudes. Que un recurso sea clínico no implica que deba transformarse en el timeline actual.

### 5.1 Summary

| Recurso               | Finalidad normativa resumida                                        | Tratamiento en Carer Record                              |
| --------------------- | ------------------------------------------------------------------- | -------------------------------------------------------- |
| `AllergyIntolerance`  | Riesgo de respuesta nociva individual ante una sustancia.           | **Seleccionado MVP**.                                    |
| `AdverseEvent`        | Evento real o potencial con daño asociado a atención/investigación. | Futuro; semántica distinta de alergia.                   |
| `Condition`           | Condición, problema, diagnóstico o concepto clínico relevante.      | **Seleccionado MVP**.                                    |
| `Procedure`           | Acción realizada sobre o para un paciente.                          | Futuro; el enum local no equivale a mapper implementado. |
| `FamilyMemberHistory` | Condiciones relevantes de familiares del paciente.                  | Futuro para anamnesis ampliada.                          |
| `ClinicalImpression`  | Evaluación clínica que integra hallazgos antes de planificar.       | Futuro; requiere autoría y contexto clínico.             |
| `DetectedIssue`       | Problema real o potencial entre acciones clínicas.                  | Futuro junto con soporte de decisión.                    |

### 5.2 Diagnostics

| Recurso                 | Finalidad normativa resumida                                          | Tratamiento en Carer Record                                           |
| ----------------------- | --------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `Observation`           | Medición o aseveración simple sobre un sujeto.                        | **Seleccionado MVP**.                                                 |
| `Media`                 | Foto, audio o video clínico.                                          | Descartado: contenido multimedia sensible fuera del MVP.              |
| `DiagnosticReport`      | Informe y conclusión de pruebas, con resultados y formas presentadas. | **Futuro prioritario**; requiere vincular resultados sin duplicarlos. |
| `Specimen`              | Muestra usada para análisis.                                          | Futuro junto con laboratorio/`DiagnosticReport`.                      |
| `BodyStructure`         | Detalle anatómico no expresable solo con código.                      | Futuro si procedimientos/diagnóstico lo exigen.                       |
| `ImagingStudy`          | Representación de estudio DICOM, series e instancias.                 | Futuro; requiere integración DICOM e imágenes.                        |
| `QuestionnaireResponse` | Respuestas estructuradas a un cuestionario.                           | Futuro junto con definiciones de cuestionario.                        |
| `MolecularSequence`     | Datos primarios de secuencia biológica.                               | Descartado por alcance y sensibilidad.                                |

### 5.3 Medications

| Recurso                      | Finalidad normativa resumida                                 | Tratamiento en Carer Record                                      |
| ---------------------------- | ------------------------------------------------------------ | ---------------------------------------------------------------- |
| `MedicationRequest`          | Orden o solicitud de medicamento y sus instrucciones.        | **Seleccionado MVP**; no implica administración.                 |
| `MedicationAdministration`   | Evento real de administración o consumo supervisado.         | Futuro prioritario para registro de administración.              |
| `MedicationDispense`         | Entrega/dispensación de un medicamento.                      | Futuro para farmacia.                                            |
| `MedicationStatement`        | Declaración de que un paciente toma o tomó un medicamento.   | Futuro; no se confunde con orden.                                |
| `Medication`                 | Identificación/definición del producto medicamentoso.        | Futuro; la demo exige concepto codificado o contenido resoluble. |
| `MedicationKnowledge`        | Conocimiento general sobre un medicamento.                   | Descartado: base de conocimiento fuera del MVP.                  |
| `Immunization`               | Evento de administración de vacuna o registro informado.     | Futuro para historial de inmunización.                           |
| `ImmunizationEvaluation`     | Evalúa validez de una inmunización frente a recomendaciones. | Descartado: razonamiento de inmunización fuera del MVP.          |
| `ImmunizationRecommendation` | Recomendaciones de inmunización para un paciente.            | Descartado: soporte de decisión fuera del MVP.                   |

### 5.4 Care provision

| Recurso              | Finalidad normativa resumida                              | Tratamiento en Carer Record                       |
| -------------------- | --------------------------------------------------------- | ------------------------------------------------- |
| `CarePlan`           | Intención coordinada de atención durante un período.      | Futuro para planificación longitudinal.           |
| `CareTeam`           | Personas y organizaciones que coordinan/proveen atención. | Futuro; no se deriva de usuarios internos.        |
| `Goal`               | Objetivo pretendido para paciente, grupo u organización.  | Futuro junto con `CarePlan`.                      |
| `ServiceRequest`     | Solicitud de investigación, tratamiento u otro servicio.  | Futuro para órdenes no farmacológicas.            |
| `NutritionOrder`     | Orden de dieta o suplemento nutricional.                  | Futuro si se incorpora nutrición.                 |
| `VisionPrescription` | Prescripción de lentes de contacto o anteojos.            | Descartado por alcance.                           |
| `RiskAssessment`     | Estimación de resultados y probabilidades.                | Futuro sujeto a gobernanza de riesgo.             |
| `RequestGroup`       | Conjunto relacionado de solicitudes con dependencias.     | Futuro si se incorporan planes/órdenes complejas. |

### 5.5 Request and response

| Recurso                | Finalidad normativa resumida                                       | Tratamiento en Carer Record                           |
| ---------------------- | ------------------------------------------------------------------ | ----------------------------------------------------- |
| `Communication`        | Evento de transmisión de información.                              | Futuro; no equivale a una nota clínica local.         |
| `CommunicationRequest` | Solicitud de transmitir información.                               | Descartado: workflow de comunicaciones fuera del MVP. |
| `DeviceRequest`        | Solicitud de uso de un dispositivo por un paciente.                | Futuro junto con dispositivos.                        |
| `DeviceUseStatement`   | Declaración de uso de dispositivo por un paciente.                 | Futuro junto con dispositivos.                        |
| `GuidanceResponse`     | Respuesta formal de un sistema de guía/decisión.                   | Descartado: CDS fuera del MVP.                        |
| `SupplyRequest`        | Solicitud de medicamento, sustancia o dispositivo como suministro. | Descartado: logística fuera del MVP.                  |
| `SupplyDelivery`       | Registro de entrega de suministros.                                | Descartado: logística fuera del MVP.                  |

## 6. Financial

Los recursos financieros modelan cobertura, elegibilidad, reclamaciones, facturación y pagos. No son necesarios para la consulta clínica de turno y aumentan sustancialmente el alcance regulatorio y de privacidad.

### 6.1 Support

`Coverage`, `CoverageEligibilityRequest`, `CoverageEligibilityResponse`, `EnrollmentRequest` y `EnrollmentResponse` describen cobertura, elegibilidad e inscripción. Todos se descartan para la demo porque Carer Record no verifica seguros ni inscripción.

### 6.2 Billing

`Claim`, `ClaimResponse` e `Invoice` describen solicitudes de reembolso, adjudicación y factura. Todos se descartan porque no existe facturación.

### 6.3 Payment

`PaymentNotice` y `PaymentReconciliation` describen aviso y conciliación de pagos. Ambos se descartan porque no existe procesamiento financiero.

### 6.4 General financial

`Account`, `ChargeItem`, `ChargeItemDefinition`, `Contract`, `ExplanationOfBenefit` e `InsurancePlan` cubren cuentas, cargos, contratos, explicación de beneficios y planes de seguro. Todos se descartan para la demo.

## 7. Specialized

La familia Specialized contiene investigación, artefactos definicionales, medicina basada en evidencia, calidad y definiciones regulatorias de medicamentos/sustancias. Son ámbitos legítimos de FHIR, pero no datos mínimos de un timeline de atención.

### 7.1 Public health and research

`ResearchStudy` y `ResearchSubject` modelan estudios y participación de sujetos. Se descartan por falta de caso de investigación y por los requisitos éticos adicionales.

### 7.2 Definitional artifacts

`ActivityDefinition`, `DeviceDefinition`, `EventDefinition`, `ObservationDefinition`, `PlanDefinition`, `Questionnaire` y `SpecimenDefinition` definen actividades, dispositivos, eventos, observaciones, planes, formularios y clases de muestra. No representan por sí mismos un hecho del paciente. Se dejan futuros solo cuando un recurso seleccionado dependa de ellos; no se ingieren en la demo.

### 7.3 Evidence-based medicine

`ResearchDefinition`, `ResearchElementDefinition`, `Evidence`, `EvidenceVariable`, `EffectEvidenceSynthesis` y `RiskEvidenceSynthesis` representan preguntas, variables y síntesis de evidencia. Se descartan porque Carer Record no es un repositorio de evidencia ni un motor de razonamiento.

### 7.4 Quality reporting and testing

`Measure`, `MeasureReport`, `TestScript` y `TestReport` cubren medidas de calidad y pruebas de conformidad. Los dos primeros quedan futuros para analítica institucional; los dos últimos se descartan como datos ingeridos, aunque podrían inspirar pruebas técnicas fuera del pipeline clínico.

### 7.5 Medication definition

Los siguientes recursos regulatorios/descriptivos se descartan para la demo, porque el MVP solo necesita representar una solicitud clínica de medicamento y no mantener un dossier regulatorio:

- `MedicinalProduct`
- `MedicinalProductAuthorization`
- `MedicinalProductContraindication`
- `MedicinalProductIndication`
- `MedicinalProductIngredient`
- `MedicinalProductInteraction`
- `MedicinalProductManufactured`
- `MedicinalProductPackaged`
- `MedicinalProductPharmaceutical`
- `MedicinalProductUndesirableEffect`
- `SubstanceNucleicAcid`
- `SubstancePolymer`
- `SubstanceProtein`
- `SubstanceReferenceInformation`
- `SubstanceSpecification`
- `SubstanceSourceMaterial`

## 8. Lectura correcta del alcance

La frase “integración FHIR R4” significa que la frontera comprende la sintaxis, semántica básica, metadata, referencias, búsqueda, paginación y errores de R4 para el subconjunto acordado. No significa:

- implementar todos los recursos de este catálogo;
- actuar como servidor FHIR;
- declarar conformidad con cualquier Implementation Guide nacional;
- validar todos los perfiles, bindings o invariantes de R4;
- soportar XML, RDF, messaging, documentos, subscriptions, batch o transaction;
- resolver terminología, identidad maestra, consentimiento o auditoría clínica completos;
- permitir escritura hacia la FCE.

La declaración verificable de la demo es más estrecha: **cliente de ingesta FHIR R4 JSON, de solo lectura, para ocho recursos de dominio y tres recursos de infraestructura, contra una FCE simulada con datos sintéticos**.
