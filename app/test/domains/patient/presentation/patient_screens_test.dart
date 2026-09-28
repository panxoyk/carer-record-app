import 'package:carer_record_app/domains/clinical_event/domain/entities/clinical_event.dart';
import 'package:carer_record_app/domains/clinical_event/presentation/clinical_event_providers.dart';
import 'package:carer_record_app/domains/patient/domain/entities/patient.dart';
import 'package:carer_record_app/domains/patient/presentation/patient_providers.dart';
import 'package:carer_record_app/domains/patient/presentation/patient_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _patient = Patient(
  id: 'patient-id',
  externalReference: 'LOCAL-0001',
  rut: '12345678-9',
  givenName: 'Ana',
  familyName: 'Prueba',
  birthDate: null,
  careUnit: 'Medicina interna',
  bedLabel: 'Cama 12',
);

void main() {
  Widget buildScreen(Widget screen, List<Override> overrides) =>
      ProviderScope(overrides: overrides, child: MaterialApp(home: screen));

  testWidgets('shows neutral labels in the patient list', (tester) async {
    await tester.pumpWidget(
      buildScreen(const PatientsScreen(), [
        patientsProvider.overrideWith((ref) async => [_patient]),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Consulta de pacientes'), findsOneWidget);
    expect(find.text('Ficha del paciente · RUT: *****678-9'), findsOneWidget);
    expect(find.text('Casos activos'), findsNothing);
    expect(
      find.text('Pacientes hospitalizados bajo tu atención'),
      findsNothing,
    );
    expect(find.text('Ficha activa'), findsNothing);
  });

  testWidgets('shows absolute institutional time in the timeline', (
    tester,
  ) async {
    final event = ClinicalEvent(
      id: 'event-id',
      patientId: _patient.id,
      kind: 'observation',
      occurredAt: DateTime.utc(2024, 7, 1, 3, 30),
      details: ClinicalEventDetails(summary: 'Evento sintético.'),
    );
    await tester.pumpWidget(
      buildScreen(PatientDetailScreen(patientId: _patient.id), [
        patientProvider(_patient.id).overrideWith((ref) async => _patient),
        patientClinicalEventsProvider(
          _patient.id,
        ).overrideWith((ref) async => [event]),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('EVENTOS CLÍNICOS'), findsOneWidget);
    expect(find.text('Eventos clínicos'), findsOneWidget);
    expect(find.text('30-06-2024 · 23:30'), findsOneWidget);
    expect(find.text('HOY · REGISTRO CLÍNICO'), findsNothing);
    expect(find.text('Eventos recientes'), findsNothing);
  });

  testWidgets('does not state an unsupported hospitalization status', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildScreen(PatientInformationScreen(patientId: _patient.id), [
        patientProvider(_patient.id).overrideWith((ref) async => _patient),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hospitalización activa'), findsNothing);
    expect(find.text('Activo'), findsNothing);
  });
}
