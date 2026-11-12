import 'package:flutter_test/flutter_test.dart';
import 'package:carer_record_app/domains/period_summary/domain/period_summary.dart';
import 'package:carer_record_app/domains/period_summary/presentation/controllers/period_summary_controller.dart';
import 'package:carer_record_app/domains/on_device_ai/domain/synthesis_provider.dart';

final window = SummaryWindow(
  fromUtc: DateTime.utc(2026, 1, 1),
  toUtc: DateTime.utc(2026, 1, 2),
  timezone: 'UTC',
);
const kind = SummarySourceKind.contextNote;
final source = SummarySource(
  id: 's',
  kind: kind,
  title: 'Nota',
  content: 'Contenido clínico sintético',
  occurredAt: DateTime.utc(2026, 1, 1, 2),
  precision: 'instant',
);

void main() {
  test('preview reports dated and undated source counts', () async {
    final repo = FakeRepository()
      ..batch = SummarySourceBatch(
        sources: [
          source,
          const SummarySource(
            id: 'u',
            kind: kind,
            title: 'U',
            content: '',
            precision: 'undated',
          ),
        ],
        complete: true,
      );
    final c = controller(repo);
    await c.preview(window, {kind});
    expect(c.phase, PeriodSummaryPhase.preview);
    expect(c.sourceCount, 1);
    expect(c.excludedUndatedCount, 1);
  });
  test('incomplete source batch stops preview', () async {
    final c = controller(
      FakeRepository()
        ..batch = const SummarySourceBatch(sources: [], complete: false),
    );
    await c.preview(window, {kind});
    expect(c.errorCode, 'sources_incomplete');
  });
  test('empty dated source selection is rejected', () async {
    final c = controller(
      FakeRepository()
        ..batch = const SummarySourceBatch(sources: [], complete: true),
    );
    await c.preview(window, {kind});
    expect(c.errorCode, 'no_dated_sources');
  });
  test('permission denial prevents source reads', () async {
    final repo = FakeRepository();
    final c = controller(repo, allowed: false);
    await c.preview(window, {kind});
    expect(repo.sourceReads, 0);
    expect(c.errorCode, 'authorization_lost');
  });
  test('successful generation persists the draft', () async {
    final repo = FakeRepository();
    final c = controller(repo);
    await c.generate(window, {kind});
    expect(c.phase, PeriodSummaryPhase.saved);
    expect(repo.saves, 1);
  });
  test(
    'retry after ambiguous save reuses exact attempt without inference',
    () async {
      final repo = FakeRepository()..failFirstSave = true;
      final synth = FakeSynthesis();
      final c = controller(repo, synthesis: synth);
      await c.generate(window, {kind});
      final attempt = repo.attempts.first;
      expect(c.phase, PeriodSummaryPhase.saveFailed);
      await c.retrySave();
      expect(identical(repo.attempts.last, attempt), isTrue);
      expect(synth.calls, 1);
      expect(repo.attempts.last.draft.id, attempt.draft.id);
    },
  );
  test('authorization loss on save purges generated content', () async {
    final repo = FakeRepository()..authorizationLostOnSave = true;
    final c = controller(repo);
    await c.generate(window, {kind});
    expect(c.draft, isNull);
    expect(c.phase, PeriodSummaryPhase.error);
  });
  test('cancelled inference never saves its result', () async {
    final repo = FakeRepository();
    final synth = FakeSynthesis(onCall: () => true);
    final c = controller(repo, synthesis: synth);
    await c.generate(window, {kind});
    expect(c.phase, PeriodSummaryPhase.cancelled);
    expect(repo.saves, 0);
  });
  test('access revoked during inference purges and prevents save', () async {
    var allowed = true;
    final repo = FakeRepository();
    final synth = FakeSynthesis(onCall: () => allowed = false);
    final c = controller(repo, synthesis: synth, allow: () => allowed);
    await c.generate(window, {kind});
    expect(repo.saves, 0);
    expect(c.draft, isNull);
  });
  test('disposed controller cannot persist pending inference result', () async {
    final repo = FakeRepository();
    final synth = FakeSynthesis(onCall: () => false);
    final c = controller(repo, synthesis: synth);
    c.dispose();
    await c.generate(window, {kind});
    expect(repo.saves, 0);
  });
  test('runtime failure surfaces stable error code', () async {
    final c = controller(
      FakeRepository(),
      synthesis: FakeSynthesis(fail: true),
    );
    await c.generate(window, {kind});
    expect(c.phase, PeriodSummaryPhase.error);
    expect(c.errorCode, 'synthesis_synthesis_internal');
  });
}

PeriodSummaryController controller(
  FakeRepository repo, {
  FakeSynthesis? synthesis,
  bool allowed = true,
  bool Function()? allow,
}) => PeriodSummaryController(
  repository: repo,
  generator: PeriodSummaryGenerator(
    repository: repo,
    provider: synthesis ?? FakeSynthesis(),
    newId: () => 'draft-id',
    clock: () => DateTime.utc(2026, 1, 3),
  ),
  organizationId: 'org',
  hospitalizationId: 'episode',
  canContinue: allow ?? () => allowed,
);

class FakeRepository implements PeriodSummaryRepository {
  SummarySourceBatch batch = SummarySourceBatch(
    sources: [source],
    complete: true,
  );
  int sourceReads = 0, saves = 0;
  bool failFirstSave = false, authorizationLostOnSave = false;
  final attempts = <SummarySaveAttempt>[];
  @override
  Future<PeriodSummaryContext> loadContext({
    required String organizationId,
    required String hospitalizationId,
  }) async => const PeriodSummaryContext(patientId: 'patient', timezone: 'UTC');
  @override
  Future<SummarySourceBatch> loadSources({
    required String organizationId,
    required String hospitalizationId,
    required SummaryWindow window,
    required Set<SummarySourceKind> selectedKinds,
  }) async {
    sourceReads++;
    return batch;
  }

  @override
  Future<PeriodSummary> save(SummarySaveAttempt attempt) async {
    saves++;
    attempts.add(attempt);
    if (authorizationLostOnSave) {
      throw const PeriodSummaryException('authorization_lost');
    }
    if (failFirstSave && saves == 1) {
      throw const PeriodSummaryException('repository_unavailable');
    }
    return PeriodSummary(
      id: attempt.draft.id,
      organizationId: 'org',
      hospitalizationId: 'episode',
      patientId: attempt.patientId,
      window: attempt.window,
      generatedAt: attempt.draft.generatedAt,
      content: attempt.draft.prepared.content,
      modelVersion: attempt.draft.modelVersion,
      promptVersion: attempt.draft.promptVersion,
      selectedKinds: attempt.selectedKinds,
      excludedUndatedCount: attempt.draft.prepared.excludedUndatedCount,
      sources: attempt.draft.prepared.sources,
      authorId: 'author',
      createdAt: DateTime.utc(2026),
    );
  }

  @override
  Future<List<PeriodSummary>> listHistory({
    required String organizationId,
    required String hospitalizationId,
    required int limit,
    required int offset,
  }) async => [];
  @override
  Future<PeriodSummary> getOwnDetail({
    required String organizationId,
    required String hospitalizationId,
    required String summaryId,
  }) => throw UnimplementedError();
}

class FakeSynthesis implements SynthesisProvider {
  FakeSynthesis({this.onCall, this.fail = false});
  final bool Function()? onCall;
  final bool fail;
  int calls = 0;
  @override
  bool get isAvailable => true;
  @override
  String get modelVersion => 'fake';
  @override
  Future<SynthesisResult> synthesize(
    SynthesisRequest request, {
    bool Function()? isCancelled,
  }) async {
    calls++;
    final cancel = onCall?.call() ?? false;
    if (fail) throw const SynthesisException(SynthesisErrorCode.internal);
    if (cancel || (isCancelled?.call() ?? false)) {
      throw const SynthesisException(SynthesisErrorCode.cancelled);
    }
    return const SynthesisResult(
      text: 'Resumen clínico generado con datos sintéticos.',
      modelVersion: 'fake',
      promptVersion: 'v1',
    );
  }

  @override
  Future<void> dispose() async {}
}
