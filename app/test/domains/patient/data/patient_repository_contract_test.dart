import 'package:carer_record_app/domains/clinical_event/data/clinical_read_client.dart';
import 'package:carer_record_app/domains/clinical_event/data/clinical_event_repository.dart';
import 'package:carer_record_app/domains/patient/data/patient_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const org = '00000000-0000-4000-8000-000000000001';
const episode = '00000000-0000-4000-8000-000000000002';
const patient = '00000000-0000-4000-8000-000000000003';

final census = <String, dynamic>{
  'organization_id': org,
  'hospitalization_id': episode,
  'patient_id': patient,
  'hospitalization_status': 'active',
  'admitted_at': '2026-01-01T00:00:00Z',
  'discharged_at': null,
  'unit_id': '00000000-0000-4000-8000-000000000009',
  'bed_label': '12',
  'given_name': 'Ana',
  'family_name': 'Prueba',
  'birth_date': null,
};
final demographics = <String, dynamic>{
  'organization_id': org,
  'hospitalization_id': episode,
  'patient_id': patient,
  'given_name': 'Ana',
  'family_name': 'Prueba',
  'birth_date': null,
};

void main() {
  test(
    'census list builds exact view, columns, tenant filter and sort',
    () async {
      final fake = CapturingClinicalReadClient([census]);
      await PatientRepository(fake).list(org);
      final query = fake.queries.single;
      expect(query.viewName, 'clinical_census_by_hospitalization');
      expect(
        query.columns,
        'organization_id,hospitalization_id,patient_id,hospitalization_status,admitted_at,discharged_at,unit_id,bed_label,given_name,family_name,birth_date',
      );
      expect(query.organizationId, org);
      expect(query.filterColumns, ['organization_id']);
      expect(query.hospitalizationId, isNull);
      expect(query.order, [
        ClinicalReadOrder.familyName,
        ClinicalReadOrder.givenName,
      ]);
      expect(query.single, isFalse);
    },
  );

  test('detail uses exact census and demographics views and validates tenant episode', () async {
    final fake = CapturingClinicalReadClient([census, demographics]);
    final result = await PatientRepository(fake)
        .findByHospitalization(org, episode);
    expect(result?.hospitalizationId, episode);
    expect(fake.queries.map((q) => q.viewName), [
      'clinical_census_by_hospitalization',
      'clinical_patient_demographics_by_hospitalization',
    ]);
    for (final query in fake.queries) {
      expect(query.organizationId, org);
      expect(query.hospitalizationId, episode);
      expect(query.filterColumns, ['organization_id', 'hospitalization_id']);
      expect(query.single, isTrue);
      expect(query.order, isEmpty);
    }
    expect(
      fake.queries.last.columns,
      'organization_id,hospitalization_id,patient_id,given_name,family_name,birth_date',
    );
  });

  test('detail rejects cross-tenant or cross-episode demographics', () async {
    for (final mismatched in [
      {
        ...demographics,
        'organization_id': '00000000-0000-4000-8000-000000000008',
      },
      {
        ...demographics,
        'hospitalization_id': '00000000-0000-4000-8000-000000000008',
      },
      {...demographics, 'patient_id': '00000000-0000-4000-8000-000000000008'},
    ]) {
      final fake = CapturingClinicalReadClient([census, mismatched]);
      await expectLater(
        PatientRepository(fake).findByHospitalization(org, episode),
        throwsFormatException,
      );
    }
  });

  test('invalid hospitalization UUID never reaches the client', () async {
    final fake = CapturingClinicalReadClient([]);
    expect(
      await PatientRepository(fake).findByHospitalization(org, 'not-a-uuid'),
      isNull,
    );
    expect(
      await ClinicalEventRepository(fake)
          .listForHospitalization(org, 'not-a-uuid'),
      isEmpty,
    );
    expect(fake.queries, isEmpty);
  });

  test('timeline builds exact view, columns, tenant/episode filters and descending time', () async {
    final event = {
      'organization_id': org,
      'hospitalization_id': episode,
      'event_id': '00000000-0000-4000-8000-000000000004',
      'kind': 'observation',
      'occurred_at': '2026-01-01T00:00:00Z',
      'summary': 'Synthetic summary',
      'patient_id': patient,
      'created_at': '2026-01-01T00:00:00Z',
    };
    final fake = CapturingClinicalReadClient([event]);
    final result = await ClinicalEventRepository(fake)
        .listForHospitalization(org, episode);
    expect(result.single.summary, 'Synthetic summary');
    final query = fake.queries.single;
    expect(query.viewName, 'clinical_timeline_by_hospitalization');
    expect(
      query.columns,
      'organization_id,hospitalization_id,event_id,kind,occurred_at,summary,patient_id,created_at,source_kind',
    );
    expect(query.organizationId, org);
    expect(query.hospitalizationId, episode);
    expect(query.filterColumns, ['organization_id', 'hospitalization_id']);
    expect(query.order, [ClinicalReadOrder.occurredAtDescending]);
    expect(query.single, isFalse);
  });

  test('timeline refuses rows from a different tenant or episode', () async {
    final fake = CapturingClinicalReadClient([
      {
        'organization_id': org,
        'hospitalization_id': '00000000-0000-4000-8000-000000000008',
        'event_id': '00000000-0000-4000-8000-000000000004',
        'kind': 'observation',
        'occurred_at': '2026-01-01T00:00:00Z',
        'summary': 'Must not be accepted',
        'patient_id': patient,
        'created_at': '2026-01-01T00:00:00Z',
      },
    ]);
    await expectLater(
      ClinicalEventRepository(fake).listForHospitalization(org, episode),
      throwsFormatException,
    );
  });
}

class CapturingClinicalReadClient implements ClinicalReadClient {
  CapturingClinicalReadClient(this.responses);
  final List<Map<String, dynamic>> responses;
  final queries = <ClinicalReadQuery>[];
  @override
  Future<List<Map<String, dynamic>>> execute(ClinicalReadQuery query) async {
    queries.add(query);
    if (query.view == ClinicalReadView.census &&
        query.hospitalizationId != null) {
      return [responses[queries.length - 1]];
    }
    if (query.view == ClinicalReadView.demographics) return [responses.last];
    return responses;
  }
}
