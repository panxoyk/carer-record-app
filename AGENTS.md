# Instrucciones para agentes

## Antes de trabajar

- Empieza por el [índice de foundation](docs/foundation/README.md), fuente canónica para dirección y alcance.
- Para cambios funcionales, consulta [alcance](docs/foundation/03-scope.md), [arquitectura objetivo](docs/foundation/04-target-architecture.md), el flujo afectado y las [ADR](docs/foundation/decisions/index.md).
- Si cambia comportamiento, sigue la [estrategia de testing y validación](docs/foundation/11-testing-validation.md).
- El baseline documental es una fotografía histórica; verifica siempre el comportamiento implementado en código, migraciones y pruebas.

## Implementación

- Haz el cambio correcto más pequeño y mantenlo vertical por dominio. Conserva la separación `data/domain/presentation`; el acceso remoto va detrás de repositorios.
- Implementa los cambios clínicos en orden: permisos, datos/RLS, pruebas, repositorio y UI.
- RLS es la autoridad de autorización. Un guard de UI no la reemplaza. No añadas acceso clínico que no figure en el contrato de permisos.
- La Service Role Key solo puede existir en servidor. No versiones secretos, credenciales ni datos clínicos reales.
- No edites migraciones aplicadas; crea migraciones aditivas.
- Todo JSONB consumido por Flutter requiere un contrato Dart tipado; los payloads privados de servidor se validan en su propia frontera y no se exponen al cliente.
- Respeta cambios existentes y evita modificar comportamiento no relacionado.

## Validación y cierre

- No ejecutes la suite completa después de cada edición. Usa validaciones dirigidas cuando aporten feedback.
- Antes de entregar, ejecuta una vez las verificaciones de las capas modificadas según `package.json` y la estrategia de validación. Reserva la suite completa para cambios transversales o solicitudes explícitas. Ejecuta `db:reset` solo para cambios de base de datos.
- Informa las validaciones ejecutadas, omitidas o bloqueadas.
- Si cambia una decisión, alcance o contrato, actualiza las ADR y secciones de foundation afectadas; no mantengas resúmenes paralelos del estado implementado.
- Si aparecen datos reales por error, detén el trabajo, purga volúmenes, exportaciones y logs locales, y rota cualquier credencial no local expuesta antes de continuar.
- Se trabaja sobre `main`. No crees commits salvo solicitud explícita; cada commit solicitado debe contener un cambio lógico independiente.
