import '../domain/fhir_record_entities.dart';
import 'fhir_client.dart';
import 'fhir_mapper.dart';

class FhirRecordRepositoryImpl implements FhirRecordRepository {
  FhirRecordRepositoryImpl({FhirClient? client, FhirMapper? mapper})
    : _client = client ?? FhirClient(),
      _mapper = mapper ?? const FhirMapper();

  final FhirClient _client;
  final FhirMapper _mapper;

  @override
  Future<List<PatientSummary>> searchPatients(String query) async {
    if (query.trim().length < 2) return const [];
    final raw = await _client.searchPatients(query);
    return [
      for (final r in raw)
        if (r['resourceType'] == 'Patient' && r['id'] != null)
          _mapper.patient(r),
    ];
  }

  @override
  Future<ClinicalRecord> loadRecord(String patientId) async {
    final result = await _client.everything(patientId);
    final patientJson = result.resources.firstWhere(
      (r) => r['resourceType'] == 'Patient' && r['id'] == patientId,
      orElse: () => throw const FhirException('Paciente no encontrado.'),
    );
    return _mapper.record(
      patient: _mapper.patient(patientJson),
      resources: result.resources,
      truncated: result.truncated,
    );
  }
}
