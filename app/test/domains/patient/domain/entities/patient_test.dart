import 'package:carer_record_app/domains/patient/domain/entities/patient.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Patient.maskedRut', () {
    Patient patientWithRut(String? rut) => Patient(
      id: 'patient-id',
      externalReference: null,
      rut: rut,
      givenName: 'Ana',
      familyName: 'Prueba',
      birthDate: null,
      careUnit: null,
      bedLabel: null,
    );

    test('reveals only its last three digits for a valid RUT', () {
      expect(patientWithRut('12345678-9').maskedRut, '*****678-9');
      expect(patientWithRut('1234567-K').maskedRut, '****567-K');
    });

    test('returns null when the RUT is absent', () {
      expect(patientWithRut(null).maskedRut, isNull);
    });

    test('does not expose a malformed RUT', () {
      expect(patientWithRut('abcd-1').maskedRut, '****');
    });
  });

  group('Patient.matchesSearch', () {
    const patient = Patient(
      id: 'patient-id',
      externalReference: null,
      rut: '12.345.678-9',
      givenName: 'Ana',
      familyName: 'Pérez',
      birthDate: null,
      careUnit: null,
      bedLabel: null,
    );

    test('matches name terms and a formatted or unformatted RUT', () {
      expect(patient.matchesSearch('ana perez'), isTrue);
      expect(patient.matchesSearch('12345678-9'), isTrue);
      expect(patient.matchesSearch('12.345.678-9'), isTrue);
    });
  });
}
