import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/supabase_client.dart';
import '../data/patient_repository.dart';
import '../domain/entities/patient.dart';

final patientRepositoryProvider = Provider<PatientRepository>(
  (ref) => PatientRepository(ref.watch(supabaseClientProvider)),
);

final patientsProvider = FutureProvider<List<Patient>>(
  (ref) => ref.watch(patientRepositoryProvider).list(),
);

final patientProvider = FutureProvider.family<Patient?, String>(
  (ref, id) => ref.watch(patientRepositoryProvider).findById(id),
);
