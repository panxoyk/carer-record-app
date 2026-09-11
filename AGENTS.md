# Instrucciones para agentes

Lee primero `docs/development-guide.md`: contiene las decisiones de arquitectura y acuerdos de trabajo del repositorio.

- No edites migraciones existentes; añade migraciones aditivas y conserva Supabase como IaC.
- JSONB debe tiparse y validarse como objeto en base de datos y modelos.
- No expongas claves privilegiadas en Flutter ni en documentación versionada.
- Actualiza `docs/roadmap.md` y el GitHub Issue vinculado al cambiar alcance funcional.
- Ejecuta análisis/tests Flutter y las comprobaciones Supabase pertinentes antes de entregar.

La fuente instalable de estas instrucciones está en `skills/carer-record/SKILL.md`. Instálala con `./scripts/install-codex-skill.sh`.
