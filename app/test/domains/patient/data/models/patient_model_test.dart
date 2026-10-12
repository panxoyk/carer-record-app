import 'package:carer_record_app/domains/patient/data/models/patient_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final row = {
    'organization_id': '00000000-0000-4000-8000-000000000001',
    'hospitalization_id': '00000000-0000-4000-8000-000000000002',
    'patient_id': '00000000-0000-4000-8000-000000000003',
    'hospitalization_status': 'active',
    'admitted_at': '2026-01-01T00:00:00Z',
    'discharged_at': null,
    'unit_id': 'unit-a',
    'bed_label': '12',
    'given_name': 'Ana',
    'family_name': 'Prueba',
    'birth_date': null,
  };

  test('parses typed episode census columns', () {
    final patient = PatientModel.fromJson(row);
    expect(patient.hospitalizationId, '00000000-0000-4000-8000-000000000002');
    expect(patient.admittedAt, DateTime.utc(2026));
    expect(patient.unitId, 'unit-a');
  });

  test('fails when required contract fields are missing', () {
    expect(
      () => PatientModel.fromJson({...row}..remove('unit_id')),
      throwsFormatException,
    );
  });
}
