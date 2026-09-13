import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/supabase_client.dart';
import '../data/clinical_event_repository.dart';
import '../domain/entities/clinical_event.dart';

final clinicalEventRepositoryProvider = Provider<ClinicalEventRepository>(
  (ref) => ClinicalEventRepository(ref.watch(supabaseClientProvider)),
);

final patientClinicalEventsProvider =
    FutureProvider.family<List<ClinicalEvent>, String>(
      (ref, patientId) =>
          ref.watch(clinicalEventRepositoryProvider).listForPatient(patientId),
    );
