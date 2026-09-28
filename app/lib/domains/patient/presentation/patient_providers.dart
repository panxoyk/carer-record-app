import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/supabase_client.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/patient_repository.dart';
import '../domain/entities/patient.dart';

final patientRepositoryProvider = Provider<PatientRepository>(
  (ref) => PatientRepository(ref.watch(supabaseClientProvider)),
);

final patientsProvider = FutureProvider<List<Patient>>((ref) {
  final session = ref.watch(sessionProvider);
  if (session == null) return const [];
  return ref.watch(patientRepositoryProvider).list();
});

final patientProvider = FutureProvider.family<Patient?, String>((ref, id) {
  final session = ref.watch(sessionProvider);
  if (session == null) return null;
  return ref.watch(patientRepositoryProvider).findById(id);
});
