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
    'author_display_name': null,
  };

  test('parses typed view columns and uses summary text', () {
    final event = ClinicalEventModel.fromJson(row);
    expect(event.summary, 'Evento tipado.');
    expect(event.occurredAt, DateTime.utc(2024, 7, 1, 3, 30));
    expect(event.patientId, '00000000-0000-4000-8000-000000000003');
  });

  test('parses the nullable projected author display name', () {
    final event = ClinicalEventModel.fromJson({
      ...row,
      'source_kind': 'context_note',
      'author_display_name': 'Autora sintética',
    });
    expect(event.authorDisplayName, 'Autora sintética');
    expect(ClinicalEventModel.fromJson(row).authorDisplayName, isNull);
  });

  test('fails when a required contract field is missing', () {
    expect(
      () => ClinicalEventModel.fromJson({...row}..remove('summary')),
      throwsFormatException,
    );
  });

  test('defaults legacy clinical rows to the clinical_event source', () {
    final event = ClinicalEventModel.fromJson(row);
    expect(event.sourceKind, 'clinical_event');
    expect(event.isMilestone, isFalse);
    expect(event.isDictatedMilestone, isFalse);
  });

  test('parses a dictated milestone from its confirmed text only', () {
    final event = ClinicalEventModel.fromJson({
      ...row,
      'kind': 'milestone_audio',
      'source_kind': 'context_note',
      'summary': 'Texto que la autora confirmó tras la transcripción local.',
    });
    expect(event.sourceKind, 'context_note');
    expect(event.kind, 'milestone_audio');
    expect(event.isMilestone, isTrue);
    expect(event.isDictatedMilestone, isTrue);
    expect(
      event.summary,
      'Texto que la autora confirmó tras la transcripción local.',
    );
  });

  test('ignores any legacy audio column that reappears on the wire', () {
    final event = ClinicalEventModel.fromJson({
      ...row,
      'source_kind': 'context_note',
      'audio_storage_path': '00000000-0000-4000-8000-000000000002/audio.m4a',
      'audio_duration_ms': 83000,
    });
    expect(event.isMilestone, isTrue);
    expect(event.isDictatedMilestone, isFalse);
  });
}
