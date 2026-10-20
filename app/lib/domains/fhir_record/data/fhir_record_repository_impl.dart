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
  Future<PatientPage> listPatients({
    String query = '',
    String? pageToken,
  }) async {
    final page = await _client.patientsPage(query: query, pageUrl: pageToken);
    return PatientPage(
      patients: [
        for (final r in page.resources)
          if (r['resourceType'] == 'Patient' && r['id'] != null)
            _mapper.patient(r),
      ],
      nextPageToken: page.next,
    );
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
