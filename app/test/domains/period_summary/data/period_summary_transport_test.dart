import 'dart:convert';

import 'package:carer_record_app/domains/fhir_record/domain/authorized_clinical_record.dart';
import 'package:carer_record_app/domains/period_summary/data/period_summary_repository.dart';
import 'package:carer_record_app/domains/period_summary/domain/period_summary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const org = '10000000-0000-0000-0000-000000000001';
const episode = '10000000-0000-0000-0000-000000000002';
const patient = '10000000-0000-0000-0000-000000000003';
const actor = '10000000-0000-0000-0000-000000000004';
const id = '10000000-0000-0000-0000-000000000005';
final window = SummaryWindow(
  fromUtc: DateTime.utc(2026, 1, 1),
  toUtc: DateTime.utc(2026, 1, 2),
  timezone: 'UTC',
);
final attempt = SummarySaveAttempt(
  organizationId: org,
  hospitalizationId: episode,
  patientId: patient,
  window: window,
  selectedKinds: {SummarySourceKind.contextNote},
  draft: SummaryDraft(
    id: id,
    generatedAt: DateTime.utc(2026, 1, 2),
    modelVersion: 'model',
    promptVersion: 'prompt',
    prepared: PreparedSummary(
      prompt: 'PRIVATE SOURCE PROMPT NEVER PERSIST',
      content: 'Resumen sintético generado.',
      excludedUndatedCount: 0,
      sources: [
        SummarySourceReference(
          id: 'note',
          kind: 'context_note',
          occurredAt: DateTime.utc(2026, 1, 1, 1),
          precision: 'instant',
        ),
      ],
    ),
  ),
);

class _Records implements AuthorizedClinicalRecordRepository {
  _Records({this.partial = false, this.items = const []});
  final bool partial;
  final List<ClinicalTimelineItem> items;
  @override
  Future<AuthorizedClinicalRecord> load({
    required String organizationId,
    required String hospitalizationId,
    required ClinicalRecordPurpose purpose,
    String? expectedPatientId,
  }) async => AuthorizedClinicalRecord(
    status: partial ? 'partial' : 'complete',
    truncated: partial,
    freshness: const ClinicalRecordFreshness(
      retrievedAt: '2026-01-01T00:00:00Z',
    ),
    patient: const ClinicalRecordPatient(id: patient, name: 'Sintético'),
    hospitalization: const ClinicalHospitalization(
      id: episode,
      status: 'admitted',
      admittedAt: '2026-01-01T00:00:00Z',
    ),
    sections: const [],
    timeline: items,
  );
}

SupabasePeriodSummaryRepository _repo(
  Object Function(http.Request) handler, {
  _Records? records,
}) {
  final client = SupabaseClient(
    'http://localhost:54321',
    'synthetic-key',
    httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/period_summary_context')) {
        return http.Response(
          jsonEncode([
            {'patient_id': patient, 'timezone': 'UTC'},
          ]),
          200,
          request: request,
        );
      }
      final result = handler(request);
      if (result is http.Response) return result;
      return http.Response(jsonEncode(result), 200, request: request);
    }),
  );
  addTearDown(client.dispose);
  return SupabasePeriodSummaryRepository(
    client: client,
    clinicalRecords: records ?? _Records(),
    authenticatedUserId: () => actor,
  );
}

Map<String, Object?> _saved(Map<String, dynamic> payload) => {
  for (final entry in payload.entries) entry.key.substring(2): entry.value,
  'author_id': actor,
  'created_at': '2026-01-02T00:00:00Z',
};

Future<SummarySourceBatch> _sources(
  SupabasePeriodSummaryRepository repo, {
  Set<SummarySourceKind> kinds = const {SummarySourceKind.contextNote},
}) => repo.loadSources(
  organizationId: org,
  hospitalizationId: episode,
  window: window,
  selectedKinds: kinds,
);

void main() {
  test(
    'FHIR instant precision accepts a valid timestamp without seconds',
    () async {
      final repo = _repo(
        (_) => [],
        records: _Records(
          items: [
            const ClinicalTimelineItem(
              id: 'Observation/minutes',
              resourceType: 'Observation',
              title: 'Control',
              occurredAt: '2026-01-01T01:30Z',
              precision: 'instant',
            ),
          ],
        ),
      );
      final batch = await _sources(
        repo,
        kinds: {SummarySourceKind.observation},
      );
      expect(batch.sources.single.occurredAt, DateTime.utc(2026, 1, 1, 1, 30));
    },
  );
  test('save serializes only generated text and typed references, retries identical UUID', () async {
    final payloads = <Map<String, dynamic>>[];
    final repo = _repo((request) {
      expect(request.url.path, endsWith('/save_period_summary'));
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      payloads.add(payload);
      expect(request.body, isNot(contains('PRIVATE SOURCE PROMPT')));
      expect(payload['p_content'], 'Resumen sintético generado.');
      expect(
        ((payload['p_sources'] as List).single as Map<String, dynamic>).keys
            .toSet(),
        {'id', 'kind', 'occurred_at', 'precision'},
      );
      return _saved(payload);
    });
    expect((await repo.save(attempt)).id, id);
    expect((await repo.save(attempt)).id, id);
    expect(payloads[0], payloads[1]);
  });
  test('save rejects mismatched returned identity instead of accepting wrong snapshot', () async {
    final repo = _repo(
      (request) =>
          _saved(jsonDecode(request.body) as Map<String, dynamic>)
            ..['id'] = episode,
    );
    await expectLater(
      repo.save(attempt),
      throwsA(
        isA<PeriodSummaryException>().having(
          (e) => e.code,
          'code',
          'invalid_response',
        ),
      ),
    );
  });
  test(
    'draft notes cannot be consumed even if transport returns them',
    () async {
      final repo = _repo(
        (request) => http.Response(
          jsonEncode([
            {
              'id': id,
              'organization_id': org,
              'hospitalization_id': episode,
              'patient_id': patient,
              'status': 'draft',
              'content': 'Draft',
              'occurred_at': '2026-01-01T01:00:00Z',
            },
          ]),
          200,
          headers: {'content-range': '0-0/1'},
          request: request,
        ),
      );
      await expectLater(
        _sources(repo),
        throwsA(
          isA<PeriodSummaryException>().having(
            (e) => e.code,
            'code',
            'sources_incomplete',
          ),
        ),
      );
    },
  );
  test('changing source page totals fails closed', () async {
    var pages = 0;
    final repo = _repo((request) {
      final total = pages++ == 0 ? 201 : 202;
      final size = pages == 1 ? 200 : 1;
      final offset = pages == 1 ? 0 : 200;
      final rows = List.generate(
        size,
        (index) => {
          'id':
              '20000000-0000-0000-0000-${(index + offset).toString().padLeft(12, '0')}',
          'organization_id': org,
          'hospitalization_id': episode,
          'patient_id': patient,
          'status': 'confirmed',
          'content': 'Nota',
          'occurred_at': '2026-01-01T01:00:00Z',
        },
      );
      return http.Response(
        jsonEncode(rows),
        200,
        headers: {'content-range': '$offset-${offset + size - 1}/$total'},
        request: request,
      );
    });
    await expectLater(
      _sources(repo),
      throwsA(
        isA<PeriodSummaryException>().having(
          (e) => e.code,
          'code',
          'sources_incomplete',
        ),
      ),
    );
    expect(pages, 2);
  });
  test(
    'truncated FHIR blocks the summary, never returning partial sources',
    () async {
      final repo = _repo((_) => [], records: _Records(partial: true));
      await expectLater(
        _sources(repo, kinds: {SummarySourceKind.observation}),
        throwsA(
          isA<PeriodSummaryException>().having(
            (e) => e.code,
            'code',
            'sources_incomplete',
          ),
        ),
      );
    },
  );
  test(
    'FHIR calendar date preserves precision and partial date becomes undated',
    () async {
      final repo = _repo(
        (_) => [],
        records: _Records(
          items: [
            const ClinicalTimelineItem(
              id: 'Observation/1',
              resourceType: 'Observation',
              title: 'Control',
              occurredAt: '2026-01-01',
              precision: 'date',
            ),
            const ClinicalTimelineItem(
              id: 'Observation/2',
              resourceType: 'Observation',
              title: 'Control anterior',
              occurredAt: '2026-01',
              precision: 'date',
            ),
          ],
        ),
      );
      final batch = await _sources(
        repo,
        kinds: {SummarySourceKind.observation},
      );
      final prepared = prepareSummary(
        batch.sources,
        window: window,
        selectedKinds: {SummarySourceKind.observation},
      );
      expect(prepared.sources.single.toJson()['occurred_at'], '2026-01-01');
      expect(prepared.excludedUndatedCount, 1);
    },
  );
}
