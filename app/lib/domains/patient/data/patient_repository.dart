import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entities/patient.dart';
import 'models/patient_model.dart';

class PatientRepository {
  PatientRepository(this._client);

  final SupabaseClient _client;
  static const _columns =
      'id,external_reference,rut,given_name,family_name,birth_date,care_unit,bed_label';

  Future<List<PatientModel>> list({String query = ''}) async {
    final normalizedQuery = query.trim();
    final normalizedRut = Patient.normalizeRut(normalizedQuery);
    final request = _client.from('patients').select(_columns);
    if (normalizedQuery.isNotEmpty) {
      request.or(
        'given_name.ilike.%$normalizedQuery%,'
        'family_name.ilike.%$normalizedQuery%,'
        'external_reference.ilike.%$normalizedQuery%,'
        'rut.ilike.%$normalizedRut%,'
        'care_unit.ilike.%$normalizedQuery%,'
        'bed_label.ilike.%$normalizedQuery%',
      );
    }
    final rows = await request.order('family_name').order('given_name');
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
