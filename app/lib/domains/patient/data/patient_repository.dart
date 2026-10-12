import '../../clinical_event/data/clinical_read_client.dart';
import 'models/patient_model.dart';

class PatientRepository {
  PatientRepository(this._client);
  final ClinicalReadClient _client;

  Future<List<PatientModel>> list(String organizationId) async {
    final rows = await _client.execute(
      ClinicalReadQuery.census(organizationId),
    );
    for (final row in rows) {
      if (row['organization_id'] != organizationId) {
        throw const FormatException('Census row tenant mismatch');
      }
    }
    return rows.map(PatientModel.fromJson).toList();
  }

  Future<PatientModel?> findByHospitalization(
    String organizationId,
    String hospitalizationId,
  ) async {
    if (!isClinicalReadUuid(hospitalizationId)) return null;
    final rows = await _client.execute(
      ClinicalReadQuery.censusEpisode(organizationId, hospitalizationId),
    );
    if (rows.length > 1) throw const FormatException('Expected one census row');
    final row = rows.isEmpty ? null : rows.first;
    if (row == null) return null;
    _validateEpisodeRow(row, organizationId, hospitalizationId);
    final demographicsRows = await _client.execute(
      ClinicalReadQuery.demographics(organizationId, hospitalizationId),
    );
    if (demographicsRows.length > 1) {
      throw const FormatException('Expected one demographics row');
    }
    final demographics =
        demographicsRows.isEmpty ? null : demographicsRows.first;
    if (demographics == null) return null;
    _validateEpisodeRow(demographics, organizationId, hospitalizationId);
    if (row['patient_id'] != demographics['patient_id']) {
      throw const FormatException('Census and demographics patient mismatch');
    }
    return PatientModel.fromJson({...row, ...demographics});
  }
}

void _validateEpisodeRow(
  Map<String, dynamic> row,
  String organizationId,
  String hospitalizationId,
) {
  if (row['organization_id'] != organizationId ||
      row['hospitalization_id'] != hospitalizationId) {
    throw const FormatException('Clinical episode contract mismatch');
  }
}
