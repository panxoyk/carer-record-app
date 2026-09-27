# ADR-001: Repositorio canónico

- Estado: Aceptada
- Fecha: 2026-09-27
- Alcance: código, migraciones, funciones, pipeline, pruebas y documentación del prototipo

## Contexto

El prototipo combina Flutter, Supabase, Edge Functions, scripts y documentación. Mantener decisiones o esquemas operativos fuera del control de versiones produciría ambientes no reproducibles y evidencia académica difícil de auditar.

## Decisión

Este repositorio es la fuente canónica del prototipo. Código, configuración no secreta, migraciones aditivas, seed sintético, tests, ADR y protocolos de evaluación deben evolucionar juntos. La rama `main` representa la línea integrada; los artefactos generados, secretos, datos reales, volúmenes y credenciales no forman parte de la fuente canónica.

La base se reconstruye desde migraciones y seed. Un dashboard remoto puede reflejar el repositorio, pero no originar cambios no versionados. Los resultados experimentales grandes pueden almacenarse fuera, siempre que el repositorio conserve protocolo, checksum, versión y ubicación controlada.

## Alternativas consideradas

- Repositorios separados por app/backend/pipeline: mejora autonomía, pero agrega coordinación y versionado distribuido sin escala que lo justifique.
- Configurar Supabase manualmente desde dashboard: rápido para explorar, pero no reproducible ni revisable.
- Documentación externa como única fuente: facilita edición, pero rompe trazabilidad con líneas de código y commits.

## Consecuencias

- Un cambio vertical puede revisar contrato, implementación y prueba en el mismo historial.
- Las migraciones aplicadas no se editan; se agregan nuevas migraciones.
- CI puede reconstruir el estado esperado desde checkout limpio.
- El repositorio no es un almacén de evidencia clínica ni de secretos.
- La historia Git aporta procedencia, pero no sustituye auditoría de acciones clínicas.

## Riesgos

- El monorepo puede crecer y hacer CI más lento.
- Un contributor puede introducir accidentalmente PHI o secretos; se requieren prevención y respuesta.
- La configuración remota puede divergir si no se automatiza o compara.
- Enlaces `ruta:línea` pueden desplazarse; el índice debe revisarse con cambios relevantes.

## Evidencia

- `package.json:1-33` define un monorepo privado y comandos conjuntos.
- `app/`, `supabase/` y `scripts/data_pipeline/` reúnen Flutter, infraestructura y pipeline en el mismo repositorio.
- `AGENTS.md:13-18` exige infraestructura versionada, migraciones aditivas y secretos fuera de Git.
- `.github/workflows/verify.yml:19-35` reconstruye y valida las capas desde el checkout.

La evidencia respalda la práctica actual, no garantiza que una instancia remota esté libre de drift.
