# Pendientes de desarrollo

Este backlog contiene solo trabajo que afecta el desarrollo local, funcionalidades rotas, comportamiento incorrecto o la capacidad de agregar cambios con seguridad. El trabajo exclusivo de distribución y producción queda fuera de esta lista.

El trabajo se realiza directamente sobre `main`. Cada commit debe resolver un cambio lógico independiente y dejar actualizados este archivo, el roadmap, las pruebas y la documentación afectada.

## P0 - Validación pendiente

- [ ] Validar manualmente la recuperación de contraseña local con la aplicación cerrada y abierta. La URL solicitada por Flutter, `io.carerrecord.app://login-callback/recover`, debe estar permitida exactamente en Supabase.

## P1 - Comportamiento

- [ ] Eliminar o respaldar con datos reales los textos "bajo tu atención", "Ficha activa", "Hospitalización activa" y "HOY". Definir además cómo se convierte y presenta la zona horaria de eventos clínicos.
- [ ] Completar los estados de envío, error y retry en creación y actualización de usuarios, recuperación de contraseña y consultas clínicas.

## Fuera del alcance actual

No bloquean el desarrollo local: paginación para grandes volúmenes clínicos, auditoría de practitioners, ciclo de vida de cuentas, matriz de cumplimiento, reglas de integridad clínica avanzadas, inmutabilidad de eventos, almacenamiento de sesiones para datos no sintéticos, firma e identificador Android de release, permisos del artefacto release, App Links/Universal Links de producción, despliegue continuo, infraestructura cloud, backups, observabilidad y requisitos de distribución o cumplimiento para producción.
