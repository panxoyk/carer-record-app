import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../institutional/presentation/iam_providers.dart';
import '../data/clinical_event_repository.dart';
import '../domain/entities/clinical_event.dart';
import 'clinical_read_providers.dart';

final clinicalEventRepositoryProvider =
    Provider.autoDispose<ClinicalEventRepository>(
      (ref) => ClinicalEventRepository(ref.watch(clinicalReadClientProvider)),
    );

final hospitalizationClinicalEventsProvider = FutureProvider.autoDispose
    .family<List<ClinicalEvent>, String>((ref, hospitalizationId) async {
      if (ref.watch(sessionProvider) == null) return const [];
      final context = await ref.watch(iamContextProvider.future);
      if (context == null ||
          !context.allows('clinical.census.read') ||
          !context.allows('clinical.patient.read') ||
          !context.allows('clinical.timeline.read')) {
        return const [];
      }
      try {
        return await ref
            .watch(clinicalEventRepositoryProvider)
            .listForHospitalization(context.organizationId, hospitalizationId);
      } on PostgrestException catch (error) {
        if (error.code == '42501' || error.code == 'PGRST116') return const [];
        rethrow;
      }
    });
