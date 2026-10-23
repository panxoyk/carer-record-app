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
  String? birthDate = '1985-04-02',
  List<ClinicalTimelineItem>? timeline,
}) => AuthorizedClinicalRecord(
  status: status,
  truncated: false,
  freshness: const ClinicalRecordFreshness(retrievedAt: '2026-10-23T12:00:00Z'),
  patient: ClinicalRecordPatient(
    id: patientId,
    name: 'Ana FHIR Prueba',
    identifier: 'SYN-0001',
    birthDate: birthDate,
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
  bool recordDenied = false,
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
      authorizedClinicalRecordProvider(
        episodeId,
      ).overrideWith((ref) async => recordDenied ? null : record ?? fixture()),
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
      expect(find.text('Ver ficha clínica'), findsOneWidget);
      expect(find.text('Ingreso: 19-10-2026'), findsOneWidget);
      expect(find.text('Ubicación: Cama 12'), findsOneWidget);
      expect(find.textContaining('Cama Cama'), findsNothing);
      expect(find.textContaining('RUT'), findsNothing);
      final headerCard = tester.getRect(find.byType(ClinicalCard).first);
      expect(
        headerCard.width,
        closeTo(
          tester.view.physicalSize.width / tester.view.devicePixelRatio -
              2 * ClinicalSpacing.page,
          1,
        ),
      );
      await tester.tap(find.text('Ver ficha clínica'));
      await tester.pumpAndSettle();
      expect(find.text('Ana FHIR Prueba'), findsOneWidget);
      expect(find.text('Identificador'), findsOneWidget);
      expect(find.text('SYN-0001'), findsOneWidget);
      expect(find.textContaining('02-04-1985'), findsOneWidget);
      expect(find.text('Condiciones'), findsOneWidget);
      expect(find.text('Observaciones'), findsOneWidget);
      await tester.ensureVisible(find.text('Observaciones'));
      await tester.tap(find.text('Observaciones'));
      await tester.pumpAndSettle();
      expect(find.textContaining('120 mmHg'), findsOneWidget);
    },
  );

  testWidgets('birth fallback stays civil', (tester) async {
    final patient = Patient(
      organizationId: organizationId,
      hospitalizationId: episodeId,
      patientId: patientId,
      hospitalizationStatus: 'admitted',
      admittedAt: DateTime.utc(2026, 10, 20),
      dischargedAt: null,
      unitId: null,
      bedLabel: '12',
      givenName: 'Ana',
      familyName: 'Prueba',
      birthDate: DateTime(1978, 9, 15),
    );
    await tester.pumpWidget(
      testApp(patient: patient, timeline: fixture(birthDate: null)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nacimiento: 15-09-1978'), findsOneWidget);
    expect(find.textContaining('00:00'), findsNothing);
    expect(find.text('Ubicación: Cama 12'), findsOneWidget);
  });

  testWidgets('location retains one bed prefix when label already has one', (
    tester,
  ) async {
    final prefixedPatient = Patient(
      organizationId: organizationId,
      hospitalizationId: episodeId,
      patientId: patientId,
      hospitalizationStatus: 'admitted',
      admittedAt: DateTime.utc(2026, 10, 20),
      dischargedAt: null,
      unitId: null,
      bedLabel: 'Cama sintética 08',
      givenName: 'Ana',
      familyName: 'Prueba',
      birthDate: DateTime(1978, 9, 15),
    );
    await tester.pumpWidget(testApp(patient: prefixedPatient));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cama sintética 08'), findsOneWidget);
    expect(find.textContaining('Cama Cama'), findsNothing);
  });

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
      expect(find.text('Cerrada · Solo lectura'), findsOneWidget);
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
          'No fue posible cargar la ficha clínica. Se muestran solo las notas disponibles.',
        ),
        findsOneWidget,
      );
      expect(find.text('Nota confirmada'), findsOneWidget);
      expect(find.textContaining('Nota de contexto'), findsOneWidget);
      expect(find.textContaining('FHIR'), findsNothing);
      expect(find.textContaining('Dictado local'), findsNothing);
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

  testWidgets(
    'active badge is descriptive and note permission remains separate',
    (tester) async {
      await tester.pumpWidget(testApp());
      await tester.pumpAndSettle();
      expect(find.text('Hospitalización activa'), findsOneWidget);
      expect(find.byIcon(Icons.add_task_outlined), findsOneWidget);
    },
  );

  testWidgets('closed source wins a status discrepancy and hides note action', (
    tester,
  ) async {
    final closed = fixture();
    final discrepant = AuthorizedClinicalRecord(
      status: closed.status,
      truncated: false,
      freshness: closed.freshness,
      patient: closed.patient,
      hospitalization: const ClinicalHospitalization(
        id: episodeId,
        status: 'discharged',
        admittedAt: '2026-10-20T08:00:00Z',
        dischargedAt: '2026-10-22T08:00:00Z',
      ),
      sections: const [],
      timeline: const [],
    );
    await tester.pumpWidget(testApp(timeline: discrepant));
    await tester.pumpAndSettle();
    expect(find.text('Cerrada · Solo lectura'), findsOneWidget);
    expect(find.text('Hospitalización activa'), findsNothing);
    expect(find.byIcon(Icons.add_task_outlined), findsNothing);
  });

  testWidgets(
    'timeline groups instants by institutional date and preserves date precision',
    (tester) async {
      const timeline = [
        ClinicalTimelineItem(
          id: 'late',
          resourceType: 'Observation',
          title: 'Cerca de medianoche',
          occurredAt: '2026-10-23T02:30:00Z',
        ),
        ClinicalTimelineItem(
          id: 'early',
          resourceType: 'Observation',
          title: 'Tras medianoche',
          occurredAt: '2026-10-23T03:30:00Z',
        ),
        ClinicalTimelineItem(
          id: 'day',
          resourceType: 'Condition',
          title: 'Solo día',
          occurredAt: '2026-10-22',
          precision: 'date',
        ),
        ClinicalTimelineItem(
          id: 'none',
          resourceType: 'DiagnosticReport',
          title: 'Sin fecha',
        ),
      ];
      await tester.pumpWidget(testApp(timeline: fixture(timeline: timeline)));
      await tester.pumpAndSettle();
      expect(find.text('22-10-2026'), findsOneWidget);
      expect(find.text('23-10-2026'), findsOneWidget);
      expect(find.text('EVENTOS CON FECHA SIN HORA'), findsOneWidget);
      expect(find.text('SIN FECHA'), findsOneWidget);
      expect(find.textContaining('Solo fecha · 22-10-2026'), findsOneWidget);
      expect(find.textContaining('23:30'), findsOneWidget);
      expect(find.textContaining('00:30'), findsOneWidget);
    },
  );

  testWidgets('long clinical content and name fit 320px at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final longNamePatient = Patient(
      organizationId: organizationId,
      hospitalizationId: episodeId,
      patientId: patientId,
      hospitalizationStatus: 'admitted',
      admittedAt: DateTime.utc(2026),
      dischargedAt: null,
      unitId: null,
      bedLabel: null,
      givenName: 'Nombre sintético extraordinariamente extenso',
      familyName: 'Apellido compuesto de prueba prolongado',
      birthDate: DateTime(1985),
    );
    final longNote = ClinicalEvent(
      organizationId: organizationId,
      hospitalizationId: episodeId,
      id: 'long-note',
      patientId: patientId,
      kind: 'milestone_text',
      occurredAt: DateTime.utc(2026, 10, 23),
      createdAt: DateTime.utc(2026, 10, 23),
      summary: 'Contenido sintético largo ' * 20,
      sourceKind: 'context_note',
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: testApp(patient: longNamePatient, events: [longNote]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(find.textContaining('Contenido sintético largo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('record entries preserve details, references, dates and expand', (
    tester,
  ) async {
    final base = fixture();
    final fullRecord = AuthorizedClinicalRecord(
      status: 'partial',
      truncated: true,
      freshness: base.freshness,
      patient: const ClinicalRecordPatient(
        id: patientId,
        name: 'Ana FHIR Prueba',
        identifier: 'SYN-0001',
        birthDate: '1985-04-02',
        gender: 'female',
      ),
      hospitalization: base.hospitalization,
      sections: const [
        ClinicalRecordSection(
          type: 'observations',
          entries: [
            ClinicalRecordEntry(
              id: 'obs-1',
              title: 'Resultado completo con referencia',
              sourceKind: 'Observation',
              isDateOnly: false,
              detail: 'Valor íntegro · Referencia: 10–20\nSegunda línea',
              date: '2026-10-23T10:30:00Z',
            ),
            ClinicalRecordEntry(
              id: 'obs-2',
              title: 'Registro de solo fecha',
              sourceKind: 'Observation',
              isDateOnly: true,
              detail: 'Detalle íntegro',
              date: '2025-04-03',
            ),
          ],
        ),
      ],
      timeline: const [],
    );
    await tester.pumpWidget(testApp(record: fullRecord));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver ficha clínica'));
    await tester.pumpAndSettle();
    expect(find.text('La ficha puede estar incompleta.'), findsOneWidget);
    expect(find.text('Femenino'), findsOneWidget);
    expect(find.text('Observaciones'), findsOneWidget);
    await tester.tap(find.text('Observaciones'));
    await tester.pumpAndSettle();
    expect(
      find.text('Valor íntegro · Referencia: 10–20\nSegunda línea'),
      findsOneWidget,
    );
    expect(find.text('23-10-2026 · 07:30'), findsOneWidget);
    expect(find.text('Solo fecha · 03-04-2025'), findsOneWidget);
    expect(find.byIcon(Icons.calendar_today_outlined), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('denied FCE shows neutral state without patient data', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(recordDenied: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver ficha clínica'));
    await tester.pumpAndSettle();
    expect(
      find.text('No se pudo verificar el acceso. Vuelve a cargar la pantalla.'),
      findsOneWidget,
    );
    expect(find.text('Ana FHIR Prueba'), findsNothing);
  });

  testWidgets('record content fits 320px at 200 percent text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final base = fixture();
    final longRecord = AuthorizedClinicalRecord(
      status: base.status,
      truncated: base.truncated,
      freshness: base.freshness,
      patient: const ClinicalRecordPatient(
        id: patientId,
        name: 'Nombre de paciente sintético extenso',
        identifier: 'IDENTIFICADOR-SINTETICO-LARGO-001',
        gender: 'unknown',
      ),
      hospitalization: base.hospitalization,
      sections: [
        ClinicalRecordSection(
          type: 'reports',
          entries: [
            ClinicalRecordEntry(
              id: 'report-1',
              title: 'Título sintético extenso ' * 4,
              sourceKind: 'DiagnosticReport',
              isDateOnly: false,
              detail: 'Detalle clínico sintético extenso ' * 18,
              date: '2026-10-23T10:30:00Z',
            ),
          ],
        ),
      ],
      timeline: const [],
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: testApp(record: longRecord),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver ficha clínica'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Informes'));
    await tester.pumpAndSettle();
    expect(find.text('No informado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
