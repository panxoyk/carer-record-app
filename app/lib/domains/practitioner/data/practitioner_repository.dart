import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entities/practitioner.dart';
import 'models/practitioner_model.dart';

class PractitionerRepository {
  PractitionerRepository(this._client);

  final SupabaseClient _client;

  Future<Practitioner?> findById(String id) async {
    final row =
        await _client
            .from('practitioners')
            .select('id,display_name,role,status')
            .eq('id', id)
            .maybeSingle();
    return row == null ? null : PractitionerModel.fromJson(row);
  }

  Future<List<Practitioner>> list() async {
    final rows = await _client
        .from('practitioners')
        .select('id,display_name,role,status')
        .order('display_name');
    return rows.map(PractitionerModel.fromJson).toList();
  }

  Future<void> create({
    required String email,
    required String password,
    required String displayName,
    required PractitionerRole role,
  }) => _client.functions.invoke(
    'create-practitioner',
    body: {
      'email': email,
      'password': password,
      'displayName': displayName,
      'role': role.name,
    },
  );

  Future<void> update({
    required String id,
    PractitionerRole? role,
    PractitionerStatus? status,
  }) => _client
      .from('practitioners')
      .update({
        if (role != null) 'role': role.name,
        if (status != null) 'status': status.name,
      })
      .eq('id', id);
}
