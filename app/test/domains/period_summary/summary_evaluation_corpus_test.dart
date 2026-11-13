import 'package:carer_record_app/domains/period_summary/domain/period_summary.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'fixtures/summary_evaluation_corpus.dart';

void main() {
  final window = SummaryWindow.utc(
    from: evaluationFrom,
    to: evaluationNow,
    timezone: evaluationTimezone,
    now: evaluationNow,
  );

  test('corpus contains ten typed cases with review criteria', () {
    expect(summaryEvaluationCorpus, hasLength(10));
    expect(
      summaryEvaluationCorpus.map((item) => item.id).toSet(),
      hasLength(10),
    );
    for (final item in summaryEvaluationCorpus) {
      expect(item.sources, isNotEmpty, reason: item.id);
      expect(item.requiredFacts, isNotEmpty, reason: item.id);
      expect(item.prohibitedClaims, isNotEmpty, reason: item.id);
    }
  });

  test('preparation is deterministic and preserves every in-window source', () {
    for (final item in summaryEvaluationCorpus) {
      final first = prepareSummary(
        item.sources,
        window: window,
        selectedKinds: SummarySourceKind.values.toSet(),
      );
      final second = prepareSummary(
        item.sources,
        window: window,
        selectedKinds: SummarySourceKind.values.toSet(),
      );
      expect(first.prompt, second.prompt, reason: item.id);
      expect(
        first.sources.map((source) => source.id),
        second.sources.map((source) => source.id),
        reason: item.id,
      );
      final expectedIds = item.sources
          .where((source) => source.id != 'b1')
          .map((source) => source.id);
      expect(
        first.sources.map((source) => source.id),
        unorderedEquals(expectedIds),
        reason: item.id,
      );
      for (final accepted in first.sources) {
        final original = item.sources.firstWhere(
          (source) => source.id == accepted.id,
        );
        final rows = first.prompt
            .split('\n')
            .where((line) => line.startsWith('{'))
            .map((line) => jsonDecode(line) as Map<String, Object?>);
        expect(
          rows.any((row) => row['texto'] == original.content),
          isTrue,
          reason: item.id,
        );
      }
      expect(
        first.prompt,
        isNot(contains('…')),
        reason: 'preparation must not silently clip ${item.id}',
      );
    }
  });

  test('period boundary is inclusive at start and exclusive before start', () {
    final item = summaryEvaluationCorpus.singleWhere(
      (item) => item.id == 'local-boundary-and-old-history',
    );
    final prepared = prepareSummary(
      item.sources,
      window: window,
      selectedKinds: SummarySourceKind.values.toSet(),
    );
    expect(prepared.sources.map((source) => source.id), contains('b2'));
    expect(prepared.sources.map((source) => source.id), isNot(contains('b1')));
  });

  test('fixed window and 24-event day are stable synthetic inputs', () {
    expect(evaluationNow, DateTime.utc(2026, 11, 12, 15));
    expect(evaluationFrom, DateTime.utc(2026, 11, 10, 3));
    expect(evaluationTimezone, 'America/Santiago');
    final events = summaryEvaluationDay24;
    expect(summaryEvaluationCorpus, hasLength(10));
    expect(events, hasLength(24));
    expect(events.map((event) => event.id).toSet(), hasLength(24));
    expect(
      events.map((event) => event.kind).toSet(),
      SummarySourceKind.values.toSet(),
    );
    expect(events.first.occurredAt, DateTime.utc(2026, 11, 11, 3));
    expect(events.last.occurredAt, DateTime.utc(2026, 11, 12, 2));
    expect(
      events.any((event) => event.kind == SummarySourceKind.procedure),
      isTrue,
    );
    expect(
      events.any((event) => event.kind == SummarySourceKind.diagnosticReport),
      isTrue,
    );
    expect(events.any((event) => event.content.contains('mg')), isTrue);
  });
}
