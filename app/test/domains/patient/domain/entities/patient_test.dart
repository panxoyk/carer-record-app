import 'package:carer_record_app/domains/patient/domain/entities/patient.dart';
import 'package:flutter_test/flutter_test.dart';

final patient = Patient(
  organizationId: '00000000-0000-4000-8000-000000000001',
  hospitalizationId: '00000000-0000-4000-8000-000000000002',
  patientId: '00000000-0000-4000-8000-000000000003',
  hospitalizationStatus: 'active',
  admittedAt: DateTime.utc(2026),
  dischargedAt: null,
  unitId: 'unit-private-uuid',
  bedLabel: '12',
  givenName: 'Ana',
  familyName: 'Pérez',
  birthDate: null,
);

void main() {
  test('searches names only and normalizes accents', () {
    expect(patient.matchesSearch('ana perez'), isTrue);
    expect(patient.matchesSearch('12345678-9'), isFalse);
  });

  test('location contains the authorized bed label, never unit ID', () {
    expect(patient.locationLabel, 'Cama 12');
    expect(patient.locationLabel, isNot(contains('unit-private-uuid')));
  });
}
