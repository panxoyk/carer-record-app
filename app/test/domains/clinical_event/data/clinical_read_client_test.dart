import 'package:carer_record_app/domains/clinical_event/data/clinical_read_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClinicalReadQuery', () {
    const organizationId = '00000000-0000-4000-8000-000000000001';
    const episodeId = '00000000-0000-4000-8000-000000000002';

    test('the timeline selects exactly the contracted view columns', () {
      final query = ClinicalReadQuery.timeline(organizationId, episodeId);
      expect(query.columns.split(','), <String>[
        'organization_id',
        'hospitalization_id',
        'event_id',
        'kind',
        'occurred_at',
        'summary',
        'patient_id',
        'created_at',
        'source_kind',
      ]);
      expect(query.viewName, 'clinical_timeline_by_hospitalization');
    });

    test('the timeline never asks for a withdrawn audio column', () {
      // ADR-016 removed `audio_storage_path` and `audio_duration_ms` from the
      // view. Asking for them again fails the whole timeline query at runtime,
      // which is exactly what happened before this assertion existed.
      final columns = ClinicalReadQuery.timeline(
        organizationId,
        episodeId,
      ).columns;
      expect(columns, isNot(contains('audio_storage_path')));
      expect(columns, isNot(contains('audio_duration_ms')));
      expect(columns, isNot(contains('audio')));
    });

    test('every clinical read view stays tenant-scoped by construction', () {
      final queries = <ClinicalReadQuery>[
        ClinicalReadQuery.census(organizationId),
        ClinicalReadQuery.censusEpisode(organizationId, episodeId),
        ClinicalReadQuery.demographics(organizationId, episodeId),
        ClinicalReadQuery.timeline(organizationId, episodeId),
      ];
      expect(queries.first.viewName, 'fhir_clinical_census_by_hospitalization');
      expect(
        ClinicalReadQuery.censusEpisode(organizationId, episodeId).viewName,
        'clinical_census_by_hospitalization',
      );
      for (final query in queries) {
        expect(query.filterColumns.first, 'organization_id');
        expect(
          query.viewName,
          anyOf(
            'clinical_census_by_hospitalization',
            'fhir_clinical_census_by_hospitalization',
            'clinical_patient_demographics_by_hospitalization',
            'clinical_timeline_by_hospitalization',
          ),
        );
      }
    });

    test('rejects ids that are not UUIDs before touching the network', () {
      expect(isClinicalReadUuid(episodeId), isTrue);
      expect(isClinicalReadUuid('0000'), isFalse);
      expect(isClinicalReadUuid(''), isFalse);
    });
  });
}
