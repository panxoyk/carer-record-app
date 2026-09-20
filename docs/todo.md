# Pendientes de desarrollo

Este backlog contiene solo trabajo que afecta el desarrollo local, funcionalidades rotas, comportamiento incorrecto o la capacidad de agregar cambios con seguridad. El trabajo exclusivo de distribución y producción queda fuera de esta lista.

El trabajo se realiza directamente sobre `main`. Cada commit debe resolver un cambio lógico independiente y dejar actualizados este archivo, el roadmap, las pruebas y la documentación afectada.

## P0 - Funcionalidad rota

- [ ] Corregir la recuperación de contraseña local. La URL solicitada por Flutter, `io.carerrecord.app://login-callback/recover`, debe estar permitida exactamente en Supabase y probarse con la aplicación cerrada y abierta.

## P1 - Autorización y comportamiento

- [ ] Invalidar providers y datos clínicos al cerrar sesión, suspender una cuenta o cambiar su rol. Usar disposición automática donde corresponda.
- [ ] Eliminar o respaldar con datos reales los textos "bajo tu atención", "Ficha activa", "Hospitalización activa" y "HOY". Definir además cómo se convierte y presenta la zona horaria de eventos clínicos.
- [ ] Mostrar loading, error y retry en creación y actualización de usuarios, recuperación de contraseña y consultas clínicas.

## P1 - Cumplimiento y trazabilidad

- [ ] **Revisión previa:** definir una auditoría append-only para altas, cambios de rol, suspensiones y reactivaciones de practitioners. Acordar campos, acceso, retención local y detalle de cambios sin guardar secretos ni datos clínicos completos.
- [ ] **Revisión previa:** definir el ciclo de vida de practitioners y preservar la atribución histórica de eventos. Decidir si se prohíbe el borrado físico y cómo se representan cuentas retiradas.
- [ ] **Revisión previa:** crear una matriz de cumplimiento técnico que relacione normativa aplicable, requisito, control, implementación, prueba, evidencia y responsable.

## P2 - Escalabilidad y mantenibilidad

- [ ] Seleccionar columnas explícitas y paginar pacientes y eventos para evitar el límite silencioso de 1000 filas de la API.
- [ ] Separar `patient_screens.dart` por pantalla cuando se vuelva a modificar ese dominio; no crear abstracciones adicionales sin reutilización concreta.
- [ ] **Revisión previa:** definir reglas de integridad para nombres vacíos, fechas de nacimiento futuras, dígito verificador de RUT, relación cama/unidad y límites de tamaño y forma de JSON clínico.
- [ ] **Revisión previa:** decidir si el acceso clínico seguirá siendo institucional completo o se limitará por paciente, unidad o episodio. Crear relaciones y RLS solo después de documentar la decisión.
- [ ] **Revisión previa:** decidir si los eventos clínicos serán inmutables, cómo se representarán correcciones y qué procedencia mínima conservará cada evento.
- [ ] **Revisión previa:** determinar si las sesiones de desarrollo deben persistirse en Keychain/Keystore. Este control es obligatorio antes de admitir datos no sintéticos.
- [ ] **Instrucción suficiente:** completar la reproducibilidad nativa con el checksum del wrapper Gradle y evaluar locks y verificación de dependencias para CocoaPods y Android.

## Funcionalidades diferidas

- [ ] Implementar el pipeline real de ingesta FHIR; el código actual es solo un scaffold que valida argumentos. **Revisión previa:** definir procedencia, identificador de origen, lote, correcciones e inmutabilidad.
- [ ] Implementar `clinical-summary` únicamente después de definir su contrato, autorización clínica y tratamiento de datos sensibles; hoy responde HTTP 501. **Revisión previa:** acordar minimización, autorización por paciente, retención del proveedor y prohibiciones de reutilización o entrenamiento.

## Fuera del alcance actual

No bloquean el desarrollo local: firma e identificador Android de release, permisos del artefacto release, App Links/Universal Links de producción, despliegue continuo, infraestructura cloud, backups, observabilidad y requisitos de distribución o cumplimiento para producción.
