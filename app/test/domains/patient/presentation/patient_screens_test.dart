import 'dart:async';

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

  testWidgets(
    'shows an empty state when the authorized patient list is empty',
    (tester) async {
      await tester.pumpWidget(
        buildScreen(const PatientsScreen(), [
          patientsProvider.overrideWith((ref) async => []),
        ]),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('No hay pacientes disponibles para tu acceso.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('shows a terminal patient-list error without a retry button', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildScreen(const PatientsScreen(), [
        patientsProvider.overrideWith((ref) async => throw StateError('fallo')),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('No fue posible cargar los pacientes.'), findsOneWidget);
    expect(find.text('Reintentar'), findsNothing);
  });

  testWidgets('shows not found when the requested patient is unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildScreen(const PatientDetailScreen(patientId: 'unknown'), [
        patientProvider('unknown').overrideWith((ref) async => null),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Paciente no encontrado.'), findsOneWidget);
  });

  testWidgets('keeps the patient visible when only the timeline fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildScreen(PatientDetailScreen(patientId: _patient.id), [
        patientProvider(_patient.id).overrideWith((ref) async => _patient),
        patientClinicalEventsProvider(
          _patient.id,
        ).overrideWith((ref) async => throw StateError('fallo')),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text(_patient.fullName), findsOneWidget);
    expect(find.text('No fue posible cargar los eventos.'), findsOneWidget);
    expect(find.text('Reintentar'), findsNothing);
  });

  testWidgets(
    'refreshing the patient list starts a new query without old cards',
    (tester) async {
      final secondResult = Completer<List<Patient>>();
      var calls = 0;
      await tester.pumpWidget(
        buildScreen(const PatientsScreen(), [
          patientsProvider.overrideWith((ref) {
            calls += 1;
            return calls == 1 ? Future.value([_patient]) : secondResult.future;
          }),
        ]),
      );
      await tester.pumpAndSettle();

      final list = find.descendant(
        of: find.byType(RefreshIndicator),
        matching: find.byType(Scrollable),
      );
      await tester.fling(list, const Offset(0, 300), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(calls, 2);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(_patient.fullName), findsNothing);

      secondResult.complete([_patient]);
      await tester.pumpAndSettle();

      expect(find.text(_patient.fullName), findsOneWidget);
    },
  );

  testWidgets('refreshing the timeline reloads its patient and events', (
    tester,
  ) async {
    var patientCalls = 0;
    var eventCalls = 0;
    await tester.pumpWidget(
      buildScreen(PatientDetailScreen(patientId: _patient.id), [
        patientProvider(_patient.id).overrideWith((ref) async {
          patientCalls += 1;
          return _patient;
        }),
        patientClinicalEventsProvider(_patient.id).overrideWith((ref) async {
          eventCalls += 1;
          return const <ClinicalEvent>[];
        }),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
    await tester.pumpAndSettle();

    expect(patientCalls, 2);
    expect(eventCalls, 2);
  });
}
