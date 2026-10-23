import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../../core/network/supabase_client.dart';
import '../../institutional/presentation/iam_providers.dart';
import '../data/authorized_clinical_record_repository.dart';
import '../domain/authorized_clinical_record.dart';

final authorizedClinicalRecordRepositoryProvider =
    Provider.autoDispose<AuthorizedClinicalRecordRepository>(
      (ref) => AuthorizedClinicalRecordRepositoryImpl(
        ref.watch(supabaseClientProvider),
      ),
    );

final authorizedClinicalRecordProvider = FutureProvider.autoDispose
    .family<AuthorizedClinicalRecord?, String>((ref, hospitalizationId) async {
      if (ref.watch(sessionProvider) == null) return null;
      final context = await ref.watch(iamContextProvider.future);
      if (context == null ||
          !context.allows('clinical.census.read') ||
          !context.allows('clinical.patient.read')) {
        return null;
      }
      try {
        return await ref
            .watch(authorizedClinicalRecordRepositoryProvider)
            .load(
              organizationId: context.organizationId,
              hospitalizationId: hospitalizationId,
              purpose: ClinicalRecordPurpose.record,
            );
      } on ClinicalAuthorizationLost {
        return null;
      }
    });

final authorizedClinicalTimelineProvider = FutureProvider.autoDispose
    .family<AuthorizedClinicalRecord?, String>((ref, hospitalizationId) async {
      if (ref.watch(sessionProvider) == null) return null;
      final context = await ref.watch(iamContextProvider.future);
      if (context == null ||
          !context.allows('clinical.census.read') ||
          !context.allows('clinical.patient.read') ||
          !context.allows('clinical.timeline.read')) {
        return null;
      }
      try {
        return await ref
            .watch(authorizedClinicalRecordRepositoryProvider)
            .load(
              organizationId: context.organizationId,
              hospitalizationId: hospitalizationId,
              purpose: ClinicalRecordPurpose.timeline,
            );
      } on ClinicalAuthorizationLost {
        return null;
      }
    });
