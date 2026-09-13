import 'package:carer_record_app/domains/patient/domain/entities/patient.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  test('masks an eight-digit RUT except for its last three digits', () {
    expect(patientWithRut('12345678-9').maskedRut, '*****678-9');
  });

  test('masks a seven-digit RUT except for its last three digits', () {
    expect(patientWithRut('1234567-K').maskedRut, '****567-K');
  });

  test('keeps an absent RUT absent', () {
    expect(patientWithRut(null).maskedRut, isNull);
  });

  test('does not expose an unexpected RUT representation', () {
    expect(patientWithRut('abcd-1').maskedRut, '****');
  });
}
