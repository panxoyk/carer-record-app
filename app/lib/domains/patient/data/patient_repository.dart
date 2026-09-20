import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/patient_model.dart';

class PatientRepository {
  PatientRepository(this._client);

  final SupabaseClient _client;
  static const _columns =
      'id,external_reference,rut,given_name,family_name,birth_date,care_unit,bed_label';

  Future<List<PatientModel>> list() async {
    final rows = await _client
        .from('patients')
        .select(_columns)
        .order('family_name')
        .order('given_name');
    return rows.map(PatientModel.fromJson).toList();
  }

  Future<PatientModel?> findById(String id) async {
    final row =
        await _client
            .from('patients')
            .select(_columns)
            .eq('id', id)
            .maybeSingle();
    return row == null ? null : PatientModel.fromJson(row);
  }
}
