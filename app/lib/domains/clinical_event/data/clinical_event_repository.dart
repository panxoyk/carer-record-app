import 'clinical_read_client.dart';
import 'models/clinical_event_model.dart';

class ClinicalEventRepository {
  ClinicalEventRepository(this._client);
  final ClinicalReadClient _client;

  Future<List<ClinicalEventModel>> listForHospitalization(
    String organizationId,
    String hospitalizationId,
  ) async {
    if (!isClinicalReadUuid(hospitalizationId)) return const [];
    final rows = await _client.execute(
      ClinicalReadQuery.timeline(organizationId, hospitalizationId),
    );
    return rows.map((row) {
      if (row['organization_id'] != organizationId ||
          row['hospitalization_id'] != hospitalizationId) {
        throw const FormatException('Clinical timeline episode mismatch');
      }
      return ClinicalEventModel.fromJson(row);
    }).toList();
  }
}
