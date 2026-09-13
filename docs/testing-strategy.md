# Estrategia de pruebas

El objetivo de las pruebas es proteger comportamiento e invariantes, no congelar la implementación ni la apariencia de la interfaz. Esto permite refactorizar y usar asistentes de IA sin tener que reescribir pruebas que no aportan valor.

## Principios

- Probar resultados observables, permisos, contratos y efectos persistidos.
- No probar métodos privados, cantidad de llamadas internas ni estructura exacta del árbol de widgets.
- No usar golden tests o snapshots visuales por defecto.
- Cada test crea y elimina su estado, o usa una transacción con rollback. Ningún test depende del orden de ejecución ni de cantidades globales del seed.
- Un bug corregido incorpora una prueba de regresión que falle con el bug.
- Una prueba solo cambia junto con producción cuando cambia intencionalmente el contrato del producto. Un refactor interno no debe exigir cambiarla.
- Los agentes no deben modificar una expectativa solo para hacer pasar una implementación; deben explicar el cambio de contrato cuando corresponda.

## Capas prioritarias

### Base de datos

Usar pgTAP para la matriz RLS, constraints, funciones SQL y operaciones denegadas. Cada archivo debe insertar sus fixtures dentro de `begin`/`rollback`. Probar casos permitidos y denegados para anónimo, usuario sin perfil, cada rol, suspendidos y administradores.

Estas son las pruebas de mayor valor porque RLS es la autoridad de seguridad y su contrato no depende de la UI.

### Edge Functions

Probarlas como una API de caja negra contra Supabase local. Verificar status HTTP, forma mínima de la respuesta y efecto final en Auth/Postgres. Usar identificadores y correos únicos por suite.

La cobertura inicial debe incluir JWT ausente, rol incorrecto, administrador suspendido, payload inválido, creación exitosa, duplicado, rollback y protección del último administrador.

### Dart y Riverpod

Usar unit tests para modelos, normalización, validaciones, transformación de datos y decisiones de navegación/autorización. Probar providers con un
`ProviderContainer` nuevo por test y overrides de repositorios; no mockear widgets ni detalles internos de Riverpod.

Cuando una regla esté mezclada con una pantalla, extraer solo la regla pura que se necesita probar. No hacer una refactorización general solo para aumentar coverage.

### Repositorios

Preferir pruebas de contrato contra Supabase local para consultas críticas y fakes pequeños para errores, loading y cancelación. Verificar datos devueltos,
orden, filtros y errores observables, no la cadena exacta de llamadas al SDK.

### Interfaz

Mantener pocos widget tests y no validar diseño visual. Solo cubrir interacciones con lógica relevante que no sea más barata de probar debajo: submit de formulario, estado loading/error y navegación condicionada por permisos.

### Flujos completos

Mantener un conjunto mínimo de pruebas de integración para los caminos críticos: login de rol clínico y lectura de paciente, login administrativo y creación de usuario, recuperación de contraseña y pérdida de acceso tras suspensión.

## Regla por tipo de cambio

| Cambio                      | Prueba esperada                                    |
| --------------------------- | -------------------------------------------------- |
| Migración, constraint o RLS | pgTAP con caso permitido y denegado                |
| Edge Function               | Prueba HTTP de contrato e integración              |
| Modelo o regla de dominio   | Unit test Dart                                     |
| Provider o estado asíncrono | Test con `ProviderContainer` y override            |
| Repositorio o query         | Contrato contra Supabase local                     |
| Corrección de bug           | Prueba de regresión en la capa más baja posible    |
| Cambio solo visual          | Revisión manual; sin test automatizado por defecto |

La cobertura porcentual sirve como señal, no como objetivo. Se prioriza cubrir autorización, datos clínicos, transformaciones y caminos de error sobre widgets decorativos o getters triviales.
