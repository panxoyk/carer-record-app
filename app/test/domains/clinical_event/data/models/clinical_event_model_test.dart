import 'package:carer_record_app/domains/clinical_event/data/models/clinical_event_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes an event timestamp to UTC', () {
    final event = ClinicalEventModel.fromJson({
      'id': 'event-id',
      'patient_id': 'patient-id',
      'kind': 'observation',
      'occurred_at': '2024-07-01T00:30:00-03:00',
      'payload': {'summary': 'Evento sintético.'},
    });

    expect(event.occurredAt, DateTime.utc(2024, 7, 1, 3, 30));
    expect(event.occurredAt.isUtc, isTrue);
  });
}
