# Estrategia de pruebas

El MVP mantiene una suite mínima para impedir regresiones de autorización, privilegios y privacidad. No busca cobertura porcentual ni automatizar la validación de cada feature.

## Principios

- Una prueba protege un contrato estable cuyo fallo puede exponer datos, otorgar privilegios o alterar información persistida de forma relevante.
- No se añade una prueba para verificar implementación, aumentar cobertura ni acompañar cada cambio de feature.
- Cada prueba crea y elimina su estado, o usa una transacción con `rollback`. Ninguna depende del orden de ejecución ni de cantidades globales del seed.
- Un bug de autorización, privilegios o privacidad incorpora una regresión en la capa más baja que pueda demostrarlo.
- Un cambio intencional de un contrato protegido actualiza su prueba. Un refactor interno no debe requerir hacerlo.

## Suite mínima

### Base de datos

RLS es la autoridad de acceso y constituye la suite de mayor valor. Usar pgTAP cuando cambie una política, un rol, un estado de cuenta o una operación con acceso a datos. Cada comportamiento modificado incluye un caso permitido y uno denegado para los roles o estados afectados. Las operaciones administrativas se prueban explícitamente con los permisos que tengan asignados.

Probar también los privilegios de funciones SQL que respalden RLS o ejecuten con privilegios elevados. Los helpers solo se exponen a los roles requeridos; los triggers y funciones internas no se exponen como RPC.

No se prueban por defecto constraints, normalizaciones ni mapeos de datos. Solo se incorporan si protegen un requisito de privacidad, autorización o integridad clínica difícil de recuperar.

### Dart

Usar unit tests solo para reglas públicas y estables de `domain/` que protejan privacidad o un invariante de negocio relevante. No se prueba cada función de dominio: el ocultamiento de RUT es un ejemplo de regla que sí se mantiene protegida.

No probar conversiones campo a campo en `data/`, repositorios que delegan al SDK, providers, router ni widgets.

#### Estilo de tests de dominio

- Usar un archivo por entidad o regla y un `group('Tipo.miembro')` por comportamiento público protegido.
- Nombrar cada `test` por el resultado observable y la condición que lo activa; no por el método interno ni por su implementación.
- Definir fixtures locales con valores válidos por defecto y sobrescribir solo el dato relevante para el caso.
- Mantener una regla por test. Variantes del mismo contrato, como los RUT de siete y ocho dígitos, pueden verificarse juntas.
- No usar mocks, `setUp` ni helpers compartidos si el fixture local resulta más claro.

### Edge Functions

Las Edge Functions se validan con formato, lint y comprobación de tipos. Los flujos administrativos y de autenticación se revisan manualmente contra Supabase local; no se mantienen pruebas HTTP o de integración por defecto.

### Interfaz

No usar golden tests, snapshots ni widget tests. Los cambios visuales, la navegación y el comportamiento ordinario de features se revisan manualmente.

## Regla por tipo de cambio

| Cambio                                              | Prueba esperada                        |
| --------------------------------------------------- | -------------------------------------- |
| Política RLS, rol, estado o acceso a datos          | pgTAP con caso permitido y denegado    |
| Función SQL privilegiada                            | pgTAP de privilegios y acceso          |
| Edge Function                                       | Formato, lint, tipos y revisión manual |
| Regla de dominio de privacidad o invariante estable | Unit test en `domain/`                 |
| Feature ordinaria, UI o mapeo de datos              | Revisión manual                        |

## Ejecución

- Ejecutar `pnpm db:test` al modificar migraciones, RLS o funciones SQL.
- Ejecutar `pnpm functions:check` al modificar Edge Functions.
- Ejecutar `pnpm app:test` al modificar una regla de privacidad o dominio que ya tenga prueba.
- No añadir ni ejecutar pruebas de Flutter para cambios solo visuales o de comportamiento ordinario de una feature.
