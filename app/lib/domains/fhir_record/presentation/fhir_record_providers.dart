import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../../core/network/supabase_client.dart';
import '../../institutional/presentation/iam_providers.dart';
import '../data/authorized_clinical_record_repository.dart';
import '../data/clinical_attachment_repository.dart';
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

final clinicalAttachmentRepositoryProvider =
    Provider.autoDispose<ClinicalAttachmentRepository>(
      (ref) => SupabaseClinicalAttachmentRepository(
        ref.watch(supabaseClientProvider),
      ),
    );

/// One clinical photo, downloaded on demand and cached while it is shown.
/// Photos taken in the app come from Supabase Storage; photos of the clinical
/// system come from FHIR through the gateway (ADR-024).
final clinicalPhotoProvider = FutureProvider.autoDispose
    .family<ClinicalPhoto?, ClinicalPhotoRef>((ref, key) async {
      if (ref.watch(sessionProvider) == null) return null;
      final context = await ref.watch(iamContextProvider.future);
      if (context == null) return null;
      final repository = ref.watch(clinicalAttachmentRepositoryProvider);
      try {
        return switch (key.origin) {
          ClinicalPhotoOrigin.storage => await repository.downloadStored(
            key.reference,
          ),
          ClinicalPhotoOrigin.fhir => await repository.downloadFhir(
            organizationId: context.organizationId,
            hospitalizationId: key.hospitalizationId,
            documentId: key.reference,
          ),
        };
      } on ClinicalAuthorizationLost {
        return null;
      }
    });
