// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';

import 'package:carer_record_app/domains/fhir_record/data/authorized_clinical_record_repository.dart';
import 'package:carer_record_app/domains/fhir_record/domain/authorized_clinical_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> _dto({String episode = 'episode-1'}) => {
  'status': 'partial',
  'truncated': true,
  'freshness': {'retrievedAt': '2026-10-23T10:00:00Z', 'sourceUpdatedAt': null},
  'patient': {
    'id': 'internal-patient',
    'name': 'Synthetic patient',
    'identifier': null,
    'birthDate': '2001-04',
    'gender': null,
  },
  'hospitalization': {
    'id': episode,
    'status': 'admitted',
    'admittedAt': '2026-10-22T10:00:00Z',
    'dischargedAt': null,
    'unit': null,
    'bed': null,
  },
  'sections': [
    {
      'type': 'conditions',
      'entries': [
        {
          'id': 'Condition/1',
          'title': 'Condition',
          'detail': null,
          'date': '2025',
          'isDateOnly': true,
          'sourceKind': 'Condition',
        },
      ],
    },
  ],
  'timeline': [
    {
      'id': 'Observation/1',
      'occurredAt': '2025-02',
      'precision': 'date',
      'resourceType': 'Observation',
      'title': 'Observation',
      'detail': null,
    },
  ],
};

void main() {
  Future<void> rejectsDto(
    Map<String, dynamic> dto, {
    ClinicalRecordPurpose purpose = ClinicalRecordPurpose.timeline,
  }) async {
    final client = SupabaseClient(
      'http://synthetic.test',
      'synthetic-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode(dto),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
    addTearDown(client.dispose);
    await expectLater(
      AuthorizedClinicalRecordRepositoryImpl(client).load(
        organizationId: 'org',
        hospitalizationId: 'episode-1',
        purpose: purpose,
      ),
      throwsFormatException,
    );
  }

  test(
    'invokes the authorized function and preserves date-only precision',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'http://synthetic.test',
        'synthetic-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(_dto()),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final record = await AuthorizedClinicalRecordRepositoryImpl(client).load(
        organizationId: 'org',
        hospitalizationId: 'episode-1',
        expectedPatientId: 'internal-patient',
        purpose: ClinicalRecordPurpose.timeline,
      );
      expect(requests.single.url.path, '/functions/v1/clinical-record');
      expect(jsonDecode(requests.single.body), {
        'organizationId': 'org',
        'hospitalizationId': 'episode-1',
        'purpose': 'timeline',
      });
      expect(record.sections.single.entries.single.date, '2025');
      expect(record.sections.single.entries.single.isDateOnly, isTrue);
      expect(record.timeline.single.precision, 'date');
      expect(record.truncated, isTrue);
    },
  );

  test('rejects episode and expected internal patient mismatches', () async {
    final client = SupabaseClient(
      'http://synthetic.test',
      'synthetic-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode(_dto(episode: 'other')),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
    addTearDown(client.dispose);
    expect(
      () => AuthorizedClinicalRecordRepositoryImpl(client).load(
        organizationId: 'org',
        hospitalizationId: 'episode-1',
        purpose: ClinicalRecordPurpose.record,
      ),
      throwsFormatException,
    );
  });

  test('rejects a mismatched known internal patient id', () async {
    final client = SupabaseClient(
      'http://synthetic.test',
      'synthetic-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode(_dto()),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
    addTearDown(client.dispose);
    expect(
      () => AuthorizedClinicalRecordRepositoryImpl(client).load(
        organizationId: 'org',
        hospitalizationId: 'episode-1',
        expectedPatientId: 'different-patient',
        purpose: ClinicalRecordPurpose.record,
      ),
      throwsFormatException,
    );
  });

  for (final date in ['2026-99-99', '2025-02-29', '2026-04-31', '2026-00']) {
    test('rejects invalid calendar date $date', () async {
      final dto = _dto();
      final sections = dto['sections']! as List<Map<String, dynamic>>;
      final entries = sections.single['entries']! as List<Map<String, dynamic>>;
      entries.single['date'] = date;
      await rejectsDto(dto);
    });
  }

  for (final instant in [
    '2026-02-30T10:00:00Z',
    '2026-10-23T25:00:00Z',
    '2026-10-23T10:00:00+15:00',
  ]) {
    test('rejects invalid calendar instant $instant', () async {
      final dto = _dto();
      (dto['freshness']! as Map<String, dynamic>)['retrievedAt'] = instant;
      await rejectsDto(dto);
    });
  }

  test('record purpose rejects nonempty timeline', () async {
    await rejectsDto(_dto(), purpose: ClinicalRecordPurpose.record);
  });

  test('record purpose accepts empty timeline', () async {
    final dto = _dto()..['timeline'] = <dynamic>[];
    final client = SupabaseClient(
      'http://synthetic.test',
      'synthetic-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode(dto),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
    addTearDown(client.dispose);
    final result = await AuthorizedClinicalRecordRepositoryImpl(client).load(
      organizationId: 'org',
      hospitalizationId: 'episode-1',
      purpose: ClinicalRecordPurpose.record,
    );
    expect(result.timeline, isEmpty);
  });

  test('rejects unknown hospitalization status', () async {
    final dto = _dto();
    (dto['hospitalization']! as Map<String, dynamic>)['status'] =
        'temporarily_absent';
    await rejectsDto(dto);
  });

  for (final status in [401, 403, 404]) {
    test('maps function authorization status $status distinctly', () async {
      final client = SupabaseClient(
        'http://synthetic.test',
        'synthetic-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient(
          (request) async => http.Response(
            '{}',
            status,
            headers: {'content-type': 'application/json'},
            request: request,
          ),
        ),
      );
      addTearDown(client.dispose);
      expect(
        () => AuthorizedClinicalRecordRepositoryImpl(client).load(
          organizationId: 'org',
          hospitalizationId: 'episode',
          purpose: ClinicalRecordPurpose.record,
        ),
        throwsA(isA<ClinicalAuthorizationLost>()),
      );
    });
  }
}
