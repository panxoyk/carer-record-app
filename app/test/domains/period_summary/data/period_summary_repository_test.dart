import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as testing;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:carer_record_app/domains/fhir_record/domain/authorized_clinical_record.dart';
import 'package:carer_record_app/domains/period_summary/data/period_summary_repository.dart';
import 'package:carer_record_app/domains/period_summary/domain/period_summary.dart';

const org = '11111111-1111-4111-8111-111111111111';
const episode = '22222222-2222-4222-8222-222222222222';
const patient = '33333333-3333-4333-8333-333333333333';
const actor = '44444444-4444-4444-8444-444444444444';
const note = '55555555-5555-4555-8555-555555555555';

class MockClient extends testing.MockClient {
  MockClient(Future<http.Response> Function(http.Request) handler)
    : super((request) async {
        final response = await handler(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: {'content-type': 'application/json', ...response.headers},
          request: request,
        );
      });
}

class Records implements AuthorizedClinicalRecordRepository {
  Records({this.record});

  final AuthorizedClinicalRecord? record;
  ClinicalRecordRange? requestedRange;

  @override
  Future<AuthorizedClinicalRecord> load({
    required String organizationId,
    required String hospitalizationId,
    required ClinicalRecordPurpose purpose,
    String? expectedPatientId,
    ClinicalRecordRange? range,
  }) async {
    requestedRange = range;
    return record ??
        const AuthorizedClinicalRecord(
          status: 'complete',
          truncated: false,
          freshness: ClinicalRecordFreshness(
            retrievedAt: '2026-01-01T00:00:00Z',
          ),
          patient: ClinicalRecordPatient(id: patient, name: 'Synthetic'),
          hospitalization: ClinicalHospitalization(
            id: episode,
            status: 'active',
            admittedAt: '2026-01-01T00:00:00Z',
          ),
          sections: [],
          timeline: [],
        );
  }
}

void main() {
  final requests = <http.Request>[];
  late SupabasePeriodSummaryRepository repository;
  late String currentActor;
  setUp(() {
    requests.clear();
    currentActor = actor;
    final client = SupabaseClient(
      'http://localhost:54321',
      'test-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/rpc/period_summary_context')) {
          return http.Response(
            jsonEncode([
              {'patient_id': patient, 'timezone': 'America/Santiago'},
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.endsWith('/context_notes')) {
          return http.Response(
            jsonEncode([]),
            200,
            headers: {
              'content-type': 'application/json',
              'content-range': '0-0/0',
            },
          );
        }
        return http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    repository = SupabasePeriodSummaryRepository(
      client: client,
      clinicalRecords: Records(),
      authenticatedUserId: () => currentActor,
    );
  });

  test('denies unavailable context', () async {
    final client = SupabaseClient(
      'http://localhost:54321',
      'test-key',
      httpClient: MockClient((_) async => http.Response('[]', 200)),
    );
    final repo = SupabasePeriodSummaryRepository(
      client: client,
      clinicalRecords: Records(),
      authenticatedUserId: () => actor,
    );
    await expectLater(
      repo.loadContext(organizationId: org, hospitalizationId: episode),
      throwsA(isA<PeriodSummaryException>()),
    );
  });
  test('loads validated context and rejects malformed patient', () async {
    expect(
      (await repository.loadContext(
        organizationId: org,
        hospitalizationId: episode,
      )).timezone,
      'America/Santiago',
    );
    expect(requests.single.url.path, endsWith('/rpc/period_summary_context'));
  });
  test(
    'fails closed when the authorized organization is outside demo timezone',
    () async {
      final client = SupabaseClient(
        'http://localhost:54321',
        'test-key',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode([
              {'patient_id': patient, 'timezone': 'UTC'},
            ]),
            200,
          ),
        ),
      );
      final repo = SupabasePeriodSummaryRepository(
        client: client,
        clinicalRecords: Records(),
        authenticatedUserId: () => actor,
      );
      await expectLater(
        repo.loadContext(organizationId: org, hospitalizationId: episode),
        throwsA(
          isA<PeriodSummaryException>().having(
            (error) => error.code,
            'code',
            'timezone_mismatch',
          ),
        ),
      );
    },
  );
  test('rejects invalid identifiers before a request', () async {
    await expectLater(
      repository.loadContext(organizationId: 'x', hospitalizationId: episode),
      throwsA(isA<PeriodSummaryException>()),
    );
    expect(requests, isEmpty);
  });
  test('context request actor switch fails closed', () async {
    currentActor = actor;
    final client = SupabaseClient(
      'http://localhost:54321',
      'test-key',
      httpClient: MockClient((_) async {
        currentActor = '99999999-9999-4999-8999-999999999999';
        return http.Response(
          jsonEncode([
            {'patient_id': patient, 'timezone': 'America/Santiago'},
          ]),
          200,
        );
      }),
    );
    final repo = SupabasePeriodSummaryRepository(
      client: client,
      clinicalRecords: Records(),
      authenticatedUserId: () => currentActor,
    );
    await expectLater(
      repo.loadContext(organizationId: org, hospitalizationId: episode),
      throwsA(isA<PeriodSummaryException>()),
    );
  });
  test(
    'context notes request filters confirmed status but not author',
    () async {
      await repository.loadSources(
        organizationId: org,
        hospitalizationId: episode,
        window: SummaryWindow(
          fromUtc: DateTime.utc(2026),
          toUtc: DateTime.utc(2026, 2),
          timezone: 'UTC',
        ),
        selectedKinds: {SummarySourceKind.contextNote},
      );
      final uri = requests
          .firstWhere((r) => r.url.path.endsWith('/context_notes'))
          .url;
      expect(uri.queryParameters.keys, isNot(contains('author_id')));
      expect(uri.queryParameters['status'], 'eq.confirmed');
    },
  );
  test('empty source result is a complete batch', () async {
    final batch = await repository.loadSources(
      organizationId: org,
      hospitalizationId: episode,
      window: SummaryWindow(
        fromUtc: DateTime.utc(2026),
        toUtc: DateTime.utc(2026, 2),
        timezone: 'UTC',
      ),
      selectedKinds: {SummarySourceKind.contextNote},
    );
    expect(batch.complete, isTrue);
    expect(batch.sources, isEmpty);
  });
  test(
    'requests authorized FHIR timeline with the exact summary window',
    () async {
      final records = Records();
      final client = SupabaseClient(
        'http://localhost:54321',
        'test-key',
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode([
              {'patient_id': patient, 'timezone': 'America/Santiago'},
            ]),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      final repo = SupabasePeriodSummaryRepository(
        client: client,
        clinicalRecords: records,
        authenticatedUserId: () => actor,
      );
      final from = DateTime.utc(2026, 1, 1, 4);
      final to = DateTime.utc(2026, 1, 2, 5);
      await repo.loadSources(
        organizationId: org,
        hospitalizationId: episode,
        window: SummaryWindow(fromUtc: from, toUtc: to, timezone: 'UTC'),
        selectedKinds: {SummarySourceKind.condition},
      );
      addTearDown(client.dispose);
      expect(records.requestedRange?.fromUtc, from);
      expect(records.requestedRange?.toUtc, to);
    },
  );
  test(
    'prefers summaryDetail and falls back to detail for legacy timeline items',
    () async {
      final records = Records(
        record: AuthorizedClinicalRecord(
          status: 'complete',
          truncated: false,
          freshness: const ClinicalRecordFreshness(
            retrievedAt: '2026-01-01T00:00:00Z',
          ),
          patient: const ClinicalRecordPatient(id: patient, name: 'Synthetic'),
          hospitalization: const ClinicalHospitalization(
            id: episode,
            status: 'active',
            admittedAt: '2026-01-01T00:00:00Z',
          ),
          sections: const [],
          timeline: const [
            ClinicalTimelineItem(
              id: 'Observation/1',
              resourceType: 'Observation',
              title: 'Result',
              occurredAt: '2026-01-01',
              precision: 'date',
              detail: 'legacy detail',
              summaryDetail: 'typed summary',
            ),
            ClinicalTimelineItem(
              id: 'Observation/2',
              resourceType: 'Observation',
              title: 'Legacy',
              occurredAt: '2026-01-01',
              precision: 'date',
              detail: 'legacy only',
            ),
          ],
        ),
      );
      final client = SupabaseClient(
        'http://localhost:54321',
        'test-key',
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode([
              {'patient_id': patient, 'timezone': 'America/Santiago'},
            ]),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(client.dispose);
      final repo = SupabasePeriodSummaryRepository(
        client: client,
        clinicalRecords: records,
        authenticatedUserId: () => actor,
      );
      final batch = await repo.loadSources(
        organizationId: org,
        hospitalizationId: episode,
        window: SummaryWindow(
          fromUtc: DateTime.utc(2026),
          toUtc: DateTime.utc(2026, 2),
          timezone: 'UTC',
        ),
        selectedKinds: {SummarySourceKind.observation},
      );
      expect(batch.sources.map((source) => source.content), [
        'typed summary',
        'legacy only',
      ]);
    },
  );
  test('loads all 201 confirmed notes across exact-count pages', () async {
    final rows = List.generate(
      201,
      (index) => {
        'id': '${index.toString().padLeft(8, '0')}-1111-4111-8111-111111111111',
        'organization_id': org,
        'hospitalization_id': episode,
        'patient_id': patient,
        'status': 'confirmed',
        'occurred_at': '2026-01-01T00:00:00Z',
        'content': 'synthetic $index',
      },
    );
    final client = SupabaseClient(
      'http://localhost:54321',
      'test-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/rpc/period_summary_context')) {
          return http.Response(
            jsonEncode([
              {'patient_id': patient, 'timezone': 'America/Santiago'},
            ]),
            200,
          );
        }
        if (request.url.path.endsWith('/context_notes')) {
          final offset = int.parse(request.url.queryParameters['offset']!);
          final limit = int.parse(request.url.queryParameters['limit']!);
          return http.Response(
            jsonEncode(rows.skip(offset).take(limit).toList()),
            200,
            headers: {'content-range': '*/201'},
          );
        }
        return http.Response('[]', 200);
      }),
    );
    final repo = SupabasePeriodSummaryRepository(
      client: client,
      clinicalRecords: Records(),
      authenticatedUserId: () => actor,
    );
    final batch = await repo.loadSources(
      organizationId: org,
      hospitalizationId: episode,
      window: SummaryWindow(
        fromUtc: DateTime.utc(2026),
        toUtc: DateTime.utc(2026, 2),
        timezone: 'UTC',
      ),
      selectedKinds: {SummarySourceKind.contextNote},
    );
    expect(batch.sources, hasLength(201));
    expect(
      requests.where((r) => r.url.path.endsWith('/context_notes')),
      hasLength(2),
    );
  });
  test('history validates pagination inputs', () async {
    await expectLater(
      repository.listHistory(
        organizationId: org,
        hospitalizationId: episode,
        limit: 21,
        offset: 0,
      ),
      throwsA(isA<PeriodSummaryException>()),
    );
  });
  test('history query has author, organization and episode filters', () async {
    await repository.listHistory(
      organizationId: org,
      hospitalizationId: episode,
      limit: 5,
      offset: 0,
    );
    final uri = requests
        .firstWhere((r) => r.url.path.endsWith('/period_summaries'))
        .url;
    expect(uri.queryParameters['author_id'], contains(actor));
    expect(uri.queryParameters['organization_id'], contains(org));
    expect(uri.queryParameters['hospitalization_id'], contains(episode));
  });
  test('actor switch between query and response fails', () async {
    final client = SupabaseClient(
      'http://localhost:54321',
      'test-key',
      httpClient: MockClient((request) async {
        currentActor = '99999999-9999-4999-8999-999999999999';
        return http.Response('[]', 200);
      }),
    );
    final repo = SupabasePeriodSummaryRepository(
      client: client,
      clinicalRecords: Records(),
      authenticatedUserId: () => actor,
    );
    await expectLater(
      repo.listHistory(
        organizationId: org,
        hospitalizationId: episode,
        limit: 1,
        offset: 0,
      ),
      throwsA(isA<PeriodSummaryException>()),
    );
  });
  test('detail rejects invalid identifier without querying', () async {
    await expectLater(
      repository.getOwnDetail(
        organizationId: org,
        hospitalizationId: episode,
        summaryId: 'bad',
      ),
      throwsA(isA<PeriodSummaryException>()),
    );
    expect(requests, isEmpty);
  });
  test('rejects unknown source kind in persisted payload mapper', () async {
    final client = SupabaseClient(
      'http://localhost:54321',
      'test-key',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/rpc/period_summary_context')) {
          return http.Response(
            jsonEncode([
              {'patient_id': patient, 'timezone': 'America/Santiago'},
            ]),
            200,
          );
        }
        if (request.url.path.endsWith('/period_summaries')) {
          return http.Response(
            jsonEncode([
              {
                'id': note,
                'organization_id': org,
                'hospitalization_id': episode,
                'patient_id': patient,
                'author_id': actor,
                'timezone': 'UTC',
                'from_utc': '2026-01-01T00:00:00+00:00',
                'to_utc': '2026-02-01T00:00:00+00:00',
                'generated_at': '2026-01-01T00:00:00+00:00',
                'created_at': '2026-01-01T00:00:00+00:00',
                'content': 'summary',
                'model_version': 'm',
                'prompt_version': 'p',
                'selected_kinds': ['Mystery'],
                'excluded_undated_count': 0,
                'sources': [
                  {
                    'id': 'x',
                    'kind': 'Mystery',
                    'occurred_at': '2026-01-01T00:00:00Z',
                    'precision': 'instant',
                  },
                ],
              },
            ]),
            200,
          );
        }
        return http.Response('[]', 200);
      }),
    );
    final repo = SupabasePeriodSummaryRepository(
      client: client,
      clinicalRecords: Records(),
      authenticatedUserId: () => actor,
    );
    await expectLater(
      repo.listHistory(
        organizationId: org,
        hospitalizationId: episode,
        limit: 1,
        offset: 0,
      ),
      throwsA(isA<PeriodSummaryException>()),
    );
  });
}
