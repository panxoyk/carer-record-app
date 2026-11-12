import 'package:carer_record_app/domains/on_device_ai/domain/synthesis_provider.dart';
import 'package:carer_record_app/domains/period_summary/domain/period_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 8, 12);
  SummaryWindow window({DateTime? from, DateTime? to}) => SummaryWindow.utc(
    from: from ?? DateTime.utc(2026, 11, 8, 10),
    to: to ?? DateTime.utc(2026, 11, 8, 12),
    timezone: 'America/Santiago',
    now: now,
  );
  SummarySource source(
    String id, {
    String precision = 'instant',
    DateTime? at,
    SummarySourceKind kind = SummarySourceKind.observation,
    String content = 'valor clínico',
  }) => SummarySource(
    id: id,
    kind: kind,
    title: 'Dato',
    content: content,
    occurredAt: at ?? DateTime.utc(2026, 11, 8, 10),
    precision: precision,
  );

  test(
    'instant interval is half open, ordered, and emits minimal references',
    () {
      final result = prepareSummary(
        [source('end', at: window().toUtc), source('start'), source('start')],
        window: window(),
        selectedKinds: SummarySourceKind.values.toSet(),
      );
      expect(result.sources.map((s) => s.id), ['start']);
      expect(result.sources.single.toJson(), {
        'id': 'start',
        'kind': 'Observation',
        'occurred_at': '2026-11-08T10:00:00.000Z',
        'precision': 'instant',
      });
    },
  );

  test('date source keeps canonical calendar date and positive overlap independent of UTC previous day', () {
    final w = SummaryWindow.utc(
      from: DateTime.utc(2026, 11, 8, 3),
      to: DateTime.utc(2026, 11, 8, 4),
      timezone: 'America/Santiago',
      now: now,
    );
    final result = prepareSummary(
      [source('d', precision: 'date', at: DateTime.utc(2026, 11, 8))],
      window: w,
      selectedKinds: {SummarySourceKind.observation},
    );
    expect(result.sources.single.toJson()['occurred_at'], '2026-11-08');
    expect(result.prompt, contains('occurred_at="2026-11-08"'));
  });

  test('date day overlap excludes an episode range beginning at next local midnight', () {
    final w = SummaryWindow.utc(
      from: DateTime.utc(2026, 11, 8, 3),
      to: DateTime.utc(2026, 11, 8, 4),
      timezone: 'America/Santiago',
      now: now,
    );
    final result = prepareSummary(
      [source('d', precision: 'date', at: DateTime.utc(2026, 11, 7))],
      window: w,
      selectedKinds: {SummarySourceKind.observation},
    );
    expect(result.sources, isEmpty);
  });

  test(
    'date-only full-day window includes earliest date in positive-offset zone',
    () {
      final w = SummaryWindow.localDates(
        fromDate: DateTime(2026, 11, 8),
        throughDate: DateTime(2026, 11, 8),
        timezone: 'Asia/Tokyo',
        now: DateTime.utc(2026, 11, 10),
      );
      expect(w.fromUtc, DateTime.utc(2026, 11, 7, 15));
      expect(w.toUtc, DateTime.utc(2026, 11, 8, 15));
      final result = prepareSummary(
        [source('date', precision: 'date', at: DateTime.utc(2026, 11, 8))],
        window: w,
        selectedKinds: {SummarySourceKind.observation},
      );
      expect(result.sources.single.toJson()['occurred_at'], '2026-11-08');
    },
  );

  test(
    'procedure and diagnostic report are selected and serialized as sources',
    () {
      final selected = {
        SummarySourceKind.procedure,
        SummarySourceKind.diagnosticReport,
      };
      final result = prepareSummary(
        [
          source('procedure', kind: SummarySourceKind.procedure),
          source('report', kind: SummarySourceKind.diagnosticReport),
        ],
        window: window(),
        selectedKinds: selected,
      );
      expect(result.sources.map((item) => item.kind), [
        'DiagnosticReport',
        'Procedure',
      ]);
      expect(summaryKindValue(SummarySourceKind.procedure), 'Procedure');
      expect(
        summaryKindValue(SummarySourceKind.diagnosticReport),
        'DiagnosticReport',
      );
    },
  );

  test('date-only full-day windows survive Chile skipped midnight and use calendar arithmetic', () {
    final w = SummaryWindow.localDates(
      fromDate: DateTime(2019, 9, 8),
      throughDate: DateTime(2019, 9, 8),
      timezone: 'America/Santiago',
      now: DateTime.utc(2019, 9, 10),
    );
    expect(w.toUtc.difference(w.fromUtc), const Duration(hours: 23));
  });

  test('custom wall time rejects nonexistent spring-forward time', () {
    expect(
      () => SummaryWindow.localDateTimes(
        from: DateTime(2026, 3, 8, 2, 30),
        to: DateTime(2026, 3, 8, 3, 30),
        timezone: 'America/New_York',
        now: DateTime.utc(2026, 3, 10),
      ),
      throwsA(code('nonexistent_local_time')),
    );
  });

  test(
    'custom ambiguous wall time deterministically picks first occurrence',
    () {
      final w = SummaryWindow.localDateTimes(
        from: DateTime(2026, 11, 1, 1, 30),
        to: DateTime(2026, 11, 1, 2, 30),
        timezone: 'America/New_York',
        now: DateTime.utc(2026, 11, 2),
      );
      expect(w.fromUtc, DateTime.utc(2026, 11, 1, 5, 30));
    },
  );

  test(
    'rejects unknown source precision',
    () => expect(
      () => prepareSummary(
        [source('bad', precision: 'month')],
        window: window(),
        selectedKinds: {SummarySourceKind.observation},
      ),
      throwsA(code('invalid_source_date')),
    ),
  );
  test(
    'known instant without timestamp is invalid rather than counted undated',
    () => expect(
      () => prepareSummary(
        [
          SummarySource(
            id: 'bad',
            kind: SummarySourceKind.observation,
            title: 'x',
            content: 'x',
            precision: 'instant',
          ),
        ],
        window: window(),
        selectedKinds: {SummarySourceKind.observation},
      ),
      throwsA(code('invalid_source_date')),
    ),
  );
  test('undated entries are counted and excluded', () {
    final r = prepareSummary(
      [
        SummarySource(
          id: 'u',
          kind: SummarySourceKind.observation,
          title: 'x',
          content: 'x',
          precision: 'undated',
        ),
      ],
      window: window(),
      selectedKinds: {SummarySourceKind.observation},
    );
    expect(r.excludedUndatedCount, 1);
    expect(r.sources, isEmpty);
  });
  test('different ids are never deduplicated by same text', () {
    final r = prepareSummary(
      [source('a'), source('b')],
      window: window(),
      selectedKinds: {SummarySourceKind.observation},
    );
    expect(r.sources.map((x) => x.id), ['a', 'b']);
  });
  test('kind is part of duplicate identity', () {
    final r = prepareSummary(
      [source('same'), source('same', kind: SummarySourceKind.condition)],
      window: window(),
      selectedKinds: SummarySourceKind.values.toSet(),
    );
    expect(r.sources, hasLength(2));
  });
  test('unselected kinds are removed', () {
    final r = prepareSummary(
      [source('a'), source('b', kind: SummarySourceKind.condition)],
      window: window(),
      selectedKinds: {SummarySourceKind.condition},
    );
    expect(r.sources.single.id, 'b');
  });
  test(
    'budget counts assembled UTF-8 prompt and fails without truncation',
    () => expect(
      () => prepareSummary(
        [source('a', content: 'ñ' * 600)],
        window: window(),
        selectedKinds: {SummarySourceKind.observation},
      ),
      throwsA(code('input_over_budget')),
    ),
  );
  test('invalid and future windows are rejected', () {
    expect(
      () => SummaryWindow.utc(from: now, to: now, timezone: 'UTC', now: now),
      throwsA(code('invalid_window')),
    );
    expect(
      () => SummaryWindow.utc(
        from: now,
        to: now.add(const Duration(minutes: 2)),
        timezone: 'UTC',
        now: now,
      ),
      throwsA(code('invalid_window')),
    );
  });
  test(
    'custom local range rejects inverted range',
    () => expect(
      () => SummaryWindow.localDateTimes(
        from: DateTime(2026, 1, 2),
        to: DateTime(2026, 1, 1),
        timezone: 'UTC',
        now: DateTime.utc(2026, 2),
      ),
      throwsA(code('invalid_window')),
    ),
  );
  test(
    'invalid timezone rejected',
    () => expect(
      () => SummaryWindow.utc(
        from: DateTime.utc(2026),
        to: DateTime.utc(2026, 1, 2),
        timezone: 'Mars/Olympus',
        now: DateTime.utc(2026, 1, 3),
      ),
      throwsA(code('invalid_timezone')),
    ),
  );

  group('generation', () {
    late FakeRepository repo;
    late FakeProvider provider;
    late int ids;
    late PeriodSummaryGenerator generator;
    setUp(() {
      repo = FakeRepository();
      provider = FakeProvider();
      ids = 0;
      generator = PeriodSummaryGenerator(
        repository: repo,
        provider: provider,
        newId: () => 'id-${++ids}',
        clock: () => now,
      );
    });
    Future<SummaryDraft> run({
      bool Function()? cancelled,
      Set<SummarySourceKind>? kinds,
    }) => generator.generate(
      organizationId: 'org',
      hospitalizationId: 'episode',
      window: window(),
      selectedKinds: kinds ?? {SummarySourceKind.observation},
      isCancelled: cancelled,
    );
    test('empty selected kinds reject before loading sources', () async {
      await expectLater(run(kinds: {}), throwsA(code('empty_selection')));
      expect(repo.sourcesCalls, 0);
    });
    test('cancellation before loading prevents repository access', () async {
      await expectLater(run(cancelled: () => true), throwsA(code('cancelled')));
      expect(repo.contextCalls, 0);
    });
    test('cancellation after context prevents source load', () async {
      repo.afterContext = true;
      await expectLater(
        run(cancelled: () => repo.afterContext),
        throwsA(code('cancelled')),
      );
      expect(repo.sourcesCalls, 0);
    });
    test('context timezone must match window', () async {
      repo.timezone = 'UTC';
      await expectLater(run(), throwsA(code('timezone_mismatch')));
      expect(repo.sourcesCalls, 0);
    });
    test('incomplete source response prevents inference', () async {
      repo.complete = false;
      await expectLater(run(), throwsA(code('sources_incomplete')));
      expect(provider.calls, 0);
    });
    test('empty dated source set prevents inference', () async {
      repo.sources = [];
      await expectLater(run(), throwsA(code('no_dated_sources')));
      expect(provider.calls, 0);
    });
    test('over-budget sources prevent inference', () async {
      repo.sources = [source('big', content: 'x' * 2000)];
      await expectLater(run(), throwsA(code('input_over_budget')));
      expect(provider.calls, 0);
    });
    test('unavailable provider fails closed', () async {
      provider.available = false;
      await expectLater(run(), throwsA(code('provider_unavailable')));
    });
    test('provider SynthesisException maps to stable domain code', () async {
      provider.failure = const SynthesisException('unavailable');
      await expectLater(run(), throwsA(code('synthesis_unavailable')));
    });
    test('unexpected provider error maps to stable domain code', () async {
      provider.failure = StateError('sensitive');
      await expectLater(run(), throwsA(code('synthesis_internal')));
    });
    test('cancellation after inference discards result', () async {
      provider.cancelAfter = true;
      await expectLater(
        run(cancelled: () => provider.completed),
        throwsA(code('cancelled')),
      );
    });
    test('symbol-heavy model output is rejected', () async {
      provider.output = '!!!! 1234 #### \$\$\$\$';
      await expectLater(run(), throwsA(code('invalid_output')));
    });
    test('successful generation uses same stable UUID for inference and draft and separates prompt from result', () async {
      final draft = await run();
      expect(draft.id, 'id-1');
      expect(provider.request!.idempotencyKey, draft.id);
      expect(provider.request!.text, contains('Resume en español'));
      expect(draft.prepared.prompt, provider.request!.text);
      expect(draft.prepared.content, 'Resumen breve.');
      expect(draft.prepared.sources.single.toJson().keys, [
        'id',
        'kind',
        'occurred_at',
        'precision',
      ]);
      expect(ids, 1);
    });
  });
}

Matcher code(String value) =>
    isA<PeriodSummaryException>().having((e) => e.code, 'code', value);

class FakeRepository implements PeriodSummaryRepository {
  String timezone = 'America/Santiago';
  bool complete = true, afterContext = false;
  int contextCalls = 0, sourcesCalls = 0;
  List<SummarySource> sources = [
    SummarySource(
      id: 's1',
      kind: SummarySourceKind.observation,
      title: 'Dato',
      content: 'valor clínico',
      occurredAt: DateTime.utc(2026, 11, 8, 10),
      precision: 'instant',
    ),
  ];
  @override
  Future<PeriodSummaryContext> loadContext({
    required String organizationId,
    required String hospitalizationId,
  }) async {
    contextCalls++;
    return PeriodSummaryContext(patientId: 'patient', timezone: timezone);
  }

  @override
  Future<SummarySourceBatch> loadSources({
    required String organizationId,
    required String hospitalizationId,
    required SummaryWindow window,
    required Set<SummarySourceKind> selectedKinds,
  }) async {
    sourcesCalls++;
    return SummarySourceBatch(sources: sources, complete: complete);
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
  @override
  Future<PeriodSummary> save(SummarySaveAttempt attempt) =>
      throw UnimplementedError();
}

class FakeProvider implements SynthesisProvider {
  bool available = true, completed = false, cancelAfter = false;
  int calls = 0;
  Object? failure;
  String output = 'Resumen breve.';
  SynthesisRequest? request;
  @override
  bool get isAvailable => available;
  @override
  String get modelVersion => 'fake-model';
  @override
  Future<SynthesisResult> synthesize(
    SynthesisRequest request, {
    bool Function()? isCancelled,
  }) async {
    calls++;
    this.request = request;
    if (failure case final error?) throw error;
    completed = true;
    return SynthesisResult(
      text: output,
      modelVersion: modelVersion,
      promptVersion: request.promptVersion,
    );
  }

  @override
  Future<void> dispose() async {}
}
