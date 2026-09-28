import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/supabase_client.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/clinical_event_repository.dart';
import '../domain/entities/clinical_event.dart';

final clinicalEventRepositoryProvider = Provider<ClinicalEventRepository>(
  (ref) => ClinicalEventRepository(ref.watch(supabaseClientProvider)),
);

final patientClinicalEventsProvider =
    FutureProvider.family<List<ClinicalEvent>, String>((ref, patientId) {
      final session = ref.watch(sessionProvider);
      if (session == null) return const [];
      return ref
          .watch(clinicalEventRepositoryProvider)
          .listForPatient(patientId);
    });
