import 'package:carer_record_app/core/design_system/clinical_design_system.dart';
import 'package:carer_record_app/domains/clinical_event/domain/entities/clinical_event.dart';
import 'package:carer_record_app/domains/clinical_event/presentation/clinical_event_providers.dart';
import 'package:carer_record_app/domains/fhir_record/domain/authorized_clinical_record.dart';
import 'package:carer_record_app/domains/fhir_record/presentation/fhir_record_providers.dart';
import 'package:carer_record_app/domains/fhir_record/presentation/fhir_record_screens.dart';
import 'package:carer_record_app/domains/institutional/domain/iam_entities.dart';
import 'package:carer_record_app/domains/institutional/presentation/iam_providers.dart';
import 'package:carer_record_app/domains/patient/domain/entities/patient.dart';
import 'package:carer_record_app/domains/patient/presentation/patient_providers.dart';
import 'package:carer_record_app/domains/patient/presentation/patient_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const episodeId = 'episode-test';
const patientId = 'patient-test';
const organizationId = 'organization-test';

final censusPatient = Patient(
  organizationId: organizationId,
  hospitalizationId: episodeId,
  patientId: patientId,
  hospitalizationStatus: 'admitted',
  admittedAt: DateTime.utc(2026, 10, 20),
  dischargedAt: null,
  unitId: 'unit-secret-id',
  bedLabel: '12',
  givenName: 'Ana',
  familyName: 'Prueba',
  birthDate: DateTime(1985, 4, 2),
);

final closedPatient = Patient(
  organizationId: organizationId,
  hospitalizationId: episodeId,
  patientId: patientId,
  hospitalizationStatus: 'discharged',
  admittedAt: DateTime.utc(2026, 10, 20),
  dischargedAt: DateTime.utc(2026, 10, 22),
  unitId: null,
  bedLabel: null,
  givenName: 'Ana',
  familyName: 'Prueba',
  birthDate: DateTime(1985, 4, 2),
);

final allowedIam = IamContext(
  organizationId: organizationId,
  organizationName: 'Hospital sintético',
  profileId: 'profile-test',
  displayName: 'Persona de prueba',
  profileStatus: 'active',
  membershipId: 'membership-test',
  membershipStatus: 'active',
  permissions: const {
    'clinical.census.read',
    'clinical.patient.read',
    'clinical.timeline.read',
    'context.note.create',
    'context.note.confirm',
  },
);

AuthorizedClinicalRecord fixture({
  String status = 'complete',
  List<ClinicalTimelineItem>? timeline,
}) => AuthorizedClinicalRecord(
  status: status,
  truncated: false,
  freshness: const ClinicalRecordFreshness(retrievedAt: '2026-10-23T12:00:00Z'),
  patient: const ClinicalRecordPatient(
    id: patientId,
    name: 'Ana FHIR Prueba',
    identifier: 'SYN-0001',
    birthDate: '1985-04-02',
  ),
  hospitalization: const ClinicalHospitalization(
    id: episodeId,
    status: 'admitted',
    admittedAt: '2026-10-20T08:00:00Z',
    unit: 'Medicina',
    bed: '12',
  ),
  sections: const [
    ClinicalRecordSection(
      type: 'conditions',
      entries: [
        ClinicalRecordEntry(
          id: 'Condition/1',
          title: 'Condition name',
          sourceKind: 'Condition',
          isDateOnly: true,
          date: '2025-04-03',
        ),
      ],
    ),
    ClinicalRecordSection(
      type: 'observations',
      entries: [
        ClinicalRecordEntry(
          id: 'Observation/1',
          title: 'Presión arterial',
          sourceKind: 'Observation',
          isDateOnly: false,
          detail: '120 mmHg',
          date: '2026-10-23T10:30:00Z',
        ),
      ],
    ),
    ClinicalRecordSection(type: 'medications', entries: []),
    ClinicalRecordSection(type: 'procedures', entries: []),
    ClinicalRecordSection(type: 'reports', entries: []),
    ClinicalRecordSection(type: 'allergies', entries: []),
  ],
  timeline: timeline ?? const [],
);

ClinicalEvent noteEvent() => ClinicalEvent(
  organizationId: organizationId,
  hospitalizationId: episodeId,
  id: 'note-1',
  patientId: patientId,
  kind: 'milestone_text',
  occurredAt: DateTime.utc(2026, 10, 23, 11),
  createdAt: DateTime.utc(2026, 10, 23, 11),
  summary: 'Nota confirmada',
  sourceKind: 'context_note',
);

Widget testApp({
  Patient? patient,
  AuthorizedClinicalRecord? timeline,
  Object? timelineError,
  bool timelineDenied = false,
  AuthorizedClinicalRecord? record,
  List<ClinicalEvent> events = const [],
}) {
  final router = GoRouter(
    initialLocation: '/hospitalizations/$episodeId',
    routes: [
      GoRoute(
        path: '/hospitalizations/:id',
        builder: (_, state) =>
            PatientDetailScreen(hospitalizationId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/hospitalizations/:id/record',
        builder: (_, state) => AuthorizedClinicalRecordScreen(
          hospitalizationId: state.pathParameters['id']!,
        ),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      iamContextProvider.overrideWith((ref) async => allowedIam),
      patientProvider(episodeId)
          .overrideWith((ref) async => patient ?? censusPatient),
      hospitalizationClinicalEventsProvider(episodeId)
          .overrideWith((ref) async => events),
      authorizedClinicalTimelineProvider(episodeId).overrideWith((ref) async {
        if (timelineError != null) throw timelineError;
        if (timelineDenied) return null;
        return timeline ?? fixture();
      }),
      authorizedClinicalRecordProvider(episodeId)
          .overrideWith((ref) async => record ?? fixture()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      theme: ClinicalTheme.build(),
    ),
  );
}

void main() {
  testWidgets(
    'header links to authorized FCE and renders sections and values',
    (tester) async {
      await tester.pumpWidget(testApp());
      await tester.pumpAndSettle();
      expect(find.text('Ana Prueba'), findsOneWidget);
      expect(find.text('Ver ficha clínica electrónica'), findsOneWidget);
      await tester.tap(find.text('Ver ficha clínica electrónica'));
      await tester.pumpAndSettle();
      expect(find.text('Ana FHIR Prueba'), findsOneWidget);
      expect(find.text('Identificador: SYN-0001'), findsOneWidget);
      expect(find.textContaining('Nacimiento: 02-04-1985'), findsOneWidget);
      expect(find.text('Condiciones (1)'), findsOneWidget);
      expect(find.text('Observaciones (1)'), findsOneWidget);
      await tester.ensureVisible(find.text('Observaciones (1)'));
      await tester.tap(find.text('Observaciones (1)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('120 mmHg'), findsOneWidget);
    },
  );

  testWidgets(
    'closed hospitalization is read only and has no add-note action',
    (tester) async {
      final closedRecord = AuthorizedClinicalRecord(
        status: 'complete',
        truncated: false,
        freshness: const ClinicalRecordFreshness(
          retrievedAt: '2026-10-23T12:00:00Z',
        ),
        patient: fixture().patient,
        hospitalization: const ClinicalHospitalization(
          id: episodeId,
          status: 'discharged',
          admittedAt: '2026-10-20T08:00:00Z',
          dischargedAt: '2026-10-22T08:00:00Z',
        ),
        sections: const [],
        timeline: const [],
      );
      await tester.pumpWidget(
        testApp(patient: closedPatient, timeline: closedRecord),
      );
      await tester.pumpAndSettle();
      expect(find.text('Solo lectura'), findsOneWidget);
      expect(find.textContaining('Egreso:'), findsOneWidget);
      expect(find.byIcon(Icons.add_task_outlined), findsNothing);
    },
  );

  testWidgets('authorization lost hides patient, notes and add-note action', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(timelineDenied: true, events: [noteEvent()]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ana Prueba'), findsNothing);
    expect(find.text('Nota confirmada'), findsNothing);
    expect(find.byIcon(Icons.add_task_outlined), findsNothing);
  });

  testWidgets(
    'FHIR network error keeps notes but warns and avoids stale FHIR',
    (tester) async {
      await tester.pumpWidget(
        testApp(timelineError: StateError('offline'), events: [noteEvent()]),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'FHIR no disponible. Se muestran solo las notas autorizadas.',
        ),
        findsOneWidget,
      );
      expect(find.text('Nota confirmada'), findsOneWidget);
      expect(find.textContaining('Nota de contexto'), findsOneWidget);
    },
  );

  testWidgets(
    'date-only entries are labeled and never formatted as an instant',
    (tester) async {
      final snapshot = fixture(
        timeline: const [
          ClinicalTimelineItem(
            id: 'date-only',
            resourceType: 'Condition',
            title: 'Fecha sin hora',
            occurredAt: '2025-04-03',
            precision: 'date',
          ),
        ],
      );
      await tester.pumpWidget(testApp(timeline: snapshot));
      await tester.pumpAndSettle();
      expect(find.text('EVENTOS CON FECHA SIN HORA'), findsOneWidget);
      expect(find.textContaining('Solo fecha'), findsOneWidget);
      expect(find.textContaining('00:00'), findsNothing);
    },
  );
}
