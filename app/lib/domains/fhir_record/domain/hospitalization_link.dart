/// Id de la hospitalización de Supabase que corresponde a un paciente de FHIR.
///
/// El script `scripts/fhir-sync/generate-sync.mjs` crea esas filas con la
/// misma regla, de modo que la app abre la bitácora sin consultas extra.
/// Devuelve null si el id de FHIR no es numérico (no se puede enlazar).
String? hospitalizationIdForFhirPatient(String fhirId) {
  if (!RegExp(r'^\d{1,12}$').hasMatch(fhirId)) return null;
  return 'f1000000-0000-0000-0000-${fhirId.padLeft(12, '0')}';
}
