import 'package:carer_record_app/domains/clinical_event/data/models/clinical_event_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final row = {
    'organization_id': '00000000-0000-4000-8000-000000000001',
    'hospitalization_id': '00000000-0000-4000-8000-000000000002',
    'event_id': '00000000-0000-4000-8000-000000000004',
    'kind': 'observation',
    'occurred_at': '2024-07-01T00:30:00-03:00',
    'summary': 'Evento tipado.',
    'patient_id': '00000000-0000-4000-8000-000000000003',
    'created_at': '2024-07-01T03:30:00Z',
  };

  test('parses typed view columns and uses summary text', () {
    final event = ClinicalEventModel.fromJson(row);
    expect(event.summary, 'Evento tipado.');
    expect(event.occurredAt, DateTime.utc(2024, 7, 1, 3, 30));
    expect(event.patientId, '00000000-0000-4000-8000-000000000003');
  });

  test('fails when a required contract field is missing', () {
    expect(
      () => ClinicalEventModel.fromJson({...row}..remove('summary')),
      throwsFormatException,
    );
  });
}
