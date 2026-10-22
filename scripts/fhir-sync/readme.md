comandos para que el script tome los identificadores de los pacientes en el fhir y los pase a supabase, para identificar la bitacora de notas con el paciente

node scripts/fhir-sync/generate-sync.mjs [http://127.0.0.1:8080/fhir](http://127.0.0.1:8080/fhir)
docker ps --filter name=supabase_db --format "{{.Names}}"
docker cp scripts/fhir-sync/fhir-sync.sql supabase_db_carer-record:/tmp/fhir-sync.sql
docker exec supabase_db_carer-record psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f /tmp/fhir-sync.sql
