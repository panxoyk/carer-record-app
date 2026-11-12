import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/supabase_client.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../fhir_record/presentation/fhir_record_providers.dart';
import '../../institutional/presentation/iam_providers.dart';
import '../../on_device_ai/domain/synthesis_provider.dart';
import '../../on_device_ai/domain/local_capability_repository.dart';
import '../../on_device_ai/domain/local_capability_usage.dart';
import '../../on_device_ai/presentation/local_ai_providers.dart';
import '../data/period_summary_repository.dart';
import '../domain/period_summary.dart';
import 'controllers/period_summary_controller.dart';

final periodSummaryRepositoryProvider =
    Provider.autoDispose<PeriodSummaryRepository>((ref) {
      // Watching these identity/authority sources scopes repository lifetime to the
      // active account and organization; the repository itself remains the RLS boundary.
      ref.watch(sessionProvider);
      ref.watch(iamContextProvider);
      ref.watch(selectedOrganizationProvider);
      return SupabasePeriodSummaryRepository(
        client: ref.watch(supabaseClientProvider),
        clinicalRecords: ref.watch(authorizedClinicalRecordRepositoryProvider),
      );
    });

final periodSummaryAllowedProvider = Provider.autoDispose<bool>((ref) {
  final session = ref.watch(sessionProvider);
  final iam = ref.watch(iamContextProvider);
  if (!iam.hasValue || iam.hasError || iam.isLoading) return false;
  final selected = iam.valueOrNull;
  return session != null &&
      selected != null &&
      selected.profileStatus == 'active' &&
      selected.membershipStatus == 'active' &&
      const [
        'clinical.summary.use',
        'clinical.census.read',
        'clinical.patient.read',
        'clinical.timeline.read',
        'context.note.read',
      ].every(selected.allows);
});

final periodSummaryContextProvider = FutureProvider.autoDispose
    .family<PeriodSummaryContext, String>((ref, episodeId) async {
      final context = await ref.watch(iamContextProvider.future);
      if (!ref.watch(periodSummaryAllowedProvider) || context == null) {
        throw const PeriodSummaryException('authorization_lost');
      }
      return ref
          .watch(periodSummaryRepositoryProvider)
          .loadContext(
            organizationId: context.organizationId,
            hospitalizationId: episodeId,
          );
    });

typedef PeriodSummaryHistoryKey = ({String episodeId, int offset});
final periodSummaryHistoryProvider = FutureProvider.autoDispose
    .family<List<PeriodSummary>, PeriodSummaryHistoryKey>((ref, key) async {
      final context = await ref.watch(iamContextProvider.future);
      if (!ref.watch(periodSummaryAllowedProvider) || context == null) {
        throw const PeriodSummaryException('authorization_lost');
      }
      return ref
          .watch(periodSummaryRepositoryProvider)
          .listHistory(
            organizationId: context.organizationId,
            hospitalizationId: key.episodeId,
            limit: 20,
            offset: key.offset,
          );
    });

typedef PeriodSummaryDetailKey = ({String episodeId, String summaryId});
final periodSummaryDetailProvider = FutureProvider.autoDispose
    .family<PeriodSummary, PeriodSummaryDetailKey>((ref, key) async {
      final context = await ref.watch(iamContextProvider.future);
      if (!ref.watch(periodSummaryAllowedProvider) || context == null) {
        throw const PeriodSummaryException('authorization_lost');
      }
      return ref
          .watch(periodSummaryRepositoryProvider)
          .getOwnDetail(
            organizationId: context.organizationId,
            hospitalizationId: key.episodeId,
            summaryId: key.summaryId,
          );
    });

final periodSummaryControllerProvider = Provider.autoDispose
    .family<PeriodSummaryController, String>((ref, episodeId) {
      final context = ref.watch(iamContextProvider).valueOrNull;
      final synthesis = ref.watch(synthesisProviderProvider).valueOrNull;
      final repo = ref.watch(periodSummaryRepositoryProvider);
      final permitted = ref.watch(periodSummaryAllowedProvider);
      final actorId = ref.watch(sessionProvider)?.user.id;
      final controller = PeriodSummaryController(
        repository: repo,
        generator: PeriodSummaryGenerator(
          repository: repo,
          provider: _SummarySynthesis(
            synthesis ?? _UnavailableSynthesisProvider(),
            ref.read(localCapabilityUsageProvider),
            ref.read(_summaryInferenceGateProvider),
          ),
          newId: () => ref.read(periodSummaryIdProvider)(),
        ),
        organizationId: context?.organizationId ?? '',
        hospitalizationId: episodeId,
        canContinue: () =>
            permitted &&
            context != null &&
            actorId != null &&
            ref.read(periodSummaryAllowedProvider) &&
            ref.read(sessionProvider)?.user.id == actorId &&
            ref.read(iamContextProvider).valueOrNull?.organizationId ==
                context.organizationId,
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

final periodSummaryIdProvider = Provider<String Function()>(
  (_) => const Uuid().v4,
);

// Retain only a busy flag across screens: cancellation does not abort the
// native engine, so a second summary must wait until the first call settles.
class _SummaryInferenceGate {
  bool busy = false;
}

final _summaryInferenceGateProvider = Provider((_) => _SummaryInferenceGate());

class _SummarySynthesis implements SynthesisProvider {
  _SummarySynthesis(this.delegate, this.usage, this.gate);
  final SynthesisProvider delegate;
  final LocalCapabilityUsage usage;
  final _SummaryInferenceGate gate;
  @override
  bool get isAvailable => delegate.isAvailable;
  @override
  String get modelVersion => delegate.modelVersion;
  @override
  Future<SynthesisResult> synthesize(
    SynthesisRequest request, {
    bool Function()? isCancelled,
  }) async {
    if (gate.busy) throw const PeriodSummaryException('generation_busy');
    gate.busy = true;
    final lease = usage.acquire([LocalCapability.textAssistance]);
    try {
      return await delegate.synthesize(request, isCancelled: isCancelled);
    } finally {
      lease.release();
      gate.busy = false;
    }
  }

  @override
  Future<void> dispose() async {} // The shared session provider owns the engine.
}

class _UnavailableSynthesisProvider implements SynthesisProvider {
  @override
  bool get isAvailable => false;
  @override
  String get modelVersion => 'unavailable';
  @override
  Future<SynthesisResult> synthesize(
    SynthesisRequest request, {
    bool Function()? isCancelled,
  }) => Future.error(const PeriodSummaryException('provider_unavailable'));
  @override
  Future<void> dispose() async {}
}
