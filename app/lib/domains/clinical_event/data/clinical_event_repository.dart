import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/clinical_event_model.dart';

class ClinicalEventRepository {
  ClinicalEventRepository(this._client);

  final SupabaseClient _client;

  Future<List<ClinicalEventModel>> listForPatient(String patientId) async {
    final rows = await _client
        .from('clinical_events')
        .select()
        .eq('patient_id', patientId)
        .order('occurred_at', ascending: false);
    return rows.map(ClinicalEventModel.fromJson).toList();
  }
}
