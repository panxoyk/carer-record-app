import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../institutional/presentation/iam_providers.dart';
import '../../clinical_event/presentation/clinical_read_providers.dart';
import '../data/patient_repository.dart';
import '../domain/entities/patient.dart';

final patientRepositoryProvider = Provider.autoDispose<PatientRepository>(
  (ref) => PatientRepository(ref.watch(clinicalReadClientProvider)),
);

final patientsProvider = FutureProvider.autoDispose<List<Patient>>((ref) async {
  if (ref.watch(sessionProvider) == null) return const [];
  final context = await ref.watch(iamContextProvider.future);
  if (context == null ||
      !context.allows('clinical.census.read') ||
      !context.allows('clinical.patient.read')) {
    return const [];
  }
  try {
    return await ref
        .watch(patientRepositoryProvider)
        .list(context.organizationId);
  } on PostgrestException catch (error) {
    if (error.code == '42501' || error.code == 'PGRST116') return const [];
    rethrow;
  }
});

final patientProvider = FutureProvider.autoDispose.family<Patient?, String>((
  ref,
  hospitalizationId,
) async {
  if (ref.watch(sessionProvider) == null) return null;
  final context = await ref.watch(iamContextProvider.future);
  if (context == null ||
      !context.allows('clinical.census.read') ||
      !context.allows('clinical.patient.read')) {
    return null;
  }
  try {
    return await ref
        .watch(patientRepositoryProvider)
        .findByHospitalization(context.organizationId, hospitalizationId);
  } on PostgrestException catch (error) {
    if (error.code == '42501' || error.code == 'PGRST116') return null;
    rethrow;
  }
});
