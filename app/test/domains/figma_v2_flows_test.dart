import 'package:carer_record_app/core/design_system/clinical_design_system.dart';
import 'package:carer_record_app/core/security/biometric_lock.dart';
import 'package:carer_record_app/core/session/authorization_refresh.dart';
import 'package:carer_record_app/domains/clinical_event/domain/entities/clinical_event.dart';
import 'package:carer_record_app/domains/clinical_event/presentation/clinical_event_providers.dart';
import 'package:carer_record_app/domains/fhir_record/domain/authorized_clinical_record.dart';
import 'package:carer_record_app/domains/fhir_record/presentation/fhir_record_providers.dart';
import 'package:carer_record_app/domains/handoff/presentation/handoff_screen.dart';
import 'package:carer_record_app/domains/institutional/domain/iam_entities.dart';
import 'package:carer_record_app/domains/institutional/presentation/iam_providers.dart';
import 'package:carer_record_app/domains/patient/domain/entities/patient.dart';
import 'package:carer_record_app/domains/patient/presentation/patient_providers.dart';
import 'package:carer_record_app/domains/patient/presentation/patient_screens.dart';
import 'package:carer_record_app/domains/period_summary/presentation/period_summary_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const _org = '00000000-0000-4000-8000-000000000001';
const _episode = '00000000-0000-4000-8000-000000000002';
const _patient = '00000000-0000-4000-8000-000000000003';

final _census = Patient(
  organizationId: _org,
  hospitalizationId: _episode,
  patientId: _patient,
  hospitalizationStatus: 'admitted',
  admittedAt: DateTime.utc(2026, 10, 20),
  dischargedAt: null,
  unitId: null,
  bedLabel: '12',
  givenName: 'Ana',
  familyName: 'Prueba',
  birthDate: DateTime(1980, 4, 3),
  unitDisplayName: 'Medicina interna',
);

ClinicalRecordEntry _entry(
  String id,
  String title, {
  String? date,
  String? value,
  ClinicalValueFlag? flag,
  String? code,
  String? category,
  String? administeredAt,
  String sourceKind = 'Observation',
}) => ClinicalRecordEntry(
  id: 'demo-hapi/$sourceKind/$id',
  title: title,
  sourceKind: sourceKind,
  isDateOnly: false,
  date: date,
  value: value,
  flag: flag,
  code: code,
  category: category,
  administeredAt: administeredAt,
);

final _record = AuthorizedClinicalRecord(
  status: 'complete',
  truncated: false,
  freshness: const ClinicalRecordFreshness(retrievedAt: '2026-10-23T12:00:00Z'),
  patient: const ClinicalRecordPatient(id: _patient, name: 'Ana Prueba'),
  hospitalization: const ClinicalHospitalization(
    id: _episode,
    status: 'admitted',
    admittedAt: '2026-10-20T11:00:00Z',
    unit: 'Medicina interna',
    bed: 'Cama 12',
    attendingPhysician: 'Dra. Ana Torres',
    reason: 'Neumonía',
  ),
  sections: [
    ClinicalRecordSection(
      type: ClinicalSectionType.observations,
      entries: [
        _entry(
          'hr',
          'Frecuencia cardiaca',
          date: '2026-10-23T11:00:00Z',
          value: '112 /min',
          flag: ClinicalValueFlag.high,
          code: '8867-4',
          category: 'vital-signs',
        ),
        _entry(
          'intake',
          'Ingesta oral',
          date: '2026-10-23T14:00:00Z',
          value: '400 mL',
          category: 'fluid-intake',
        ),
        _entry(
          'urine',
          'Diuresis',
          date: '2026-10-23T14:00:00Z',
          value: '350 mL',
          category: 'fluid-output',
        ),
      ],
    ),
    ClinicalRecordSection(
      type: ClinicalSectionType.administrations,
      entries: [
        _entry(
          'dose-1',
          'Ceftriaxona 1 g',
          date: '2026-10-23T11:00:00Z',
          administeredAt: '2026-10-23T11:15:00Z',
          sourceKind: 'MedicationAdministration',
        ),
        _entry(
          'dose-2',
          'Ceftriaxona 1 g',
          date: '2026-10-23T23:00:00Z',
          sourceKind: 'MedicationAdministration',
        ),
      ],
    ),
  ],
  timeline: const [],
);

ClinicalEvent _note(String id, String summary, String profession) =>
    ClinicalEvent(
      organizationId: _org,
      hospitalizationId: _episode,
      id: id,
      patientId: _patient,
      kind: 'milestone',
      occurredAt: DateTime.utc(2026, 10, 23, 12),
      createdAt: DateTime.utc(2026, 10, 23, 12),
      summary: summary,
      sourceKind: 'context_note',
      authorDisplayName: 'Autor sintético',
      category: 'comunicacion',
      authorProfession: profession,
    );

IamContext _iam() => const IamContext(
  organizationId: _org,
  organizationName: 'Hospital sintético',
  profileId: '00000000-0000-4000-8000-000000000011',
  displayName: 'Profesional sintético',
  profileStatus: 'active',
  membershipId: '00000000-0000-4000-8000-000000000012',
  membershipStatus: 'active',
  permissions: {},
  profession: 'enfermeria',
);

Widget _app(Widget home, {List<ClinicalEvent> events = const []}) =>
    ProviderScope(
      overrides: [
        authorizationRefreshProvider.overrideWithValue(() {}),
        periodSummaryAllowedProvider.overrideWithValue(false),
        iamContextProvider.overrideWith((ref) async => _iam()),
        patientProvider(_episode).overrideWith((ref) async => _census),
        hospitalizationClinicalEventsProvider(_episode)
            .overrideWith((ref) async => events),
        authorizedClinicalTimelineProvider(_episode)
            .overrideWith((ref) async => _record),
      ],
      child: MaterialApp(theme: ClinicalTheme.build(), home: home),
    );

class _FakeAuthenticator implements BiometricAuthenticator {
  bool available = true;
  bool accept = true;
  int prompts = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return accept;
  }
}

void main() {
  test('handoff lists recent changes and doses without administration', () {
    final summary = HandoffSummary.build(
      patient: _census,
      record: _record,
      events: [_note('n1', 'Se informa al equipo.', 'enfermeria')],
      now: DateTime(2026, 10, 23, 10),
    );
    expect(summary.context, contains('Medicina interna'));
    expect(summary.shift, '08:00–16:00');
    final current = summary.sections.first.lines;
    expect(current, contains('Motivo: Neumonía'));
    expect(current, contains('Médico tratante: Dra. Ana Torres'));
    expect(current.last, contains('Frecuencia cardiaca'));
    expect(summary.sections[1].lines.single, contains('Se informa al equipo.'));
    final pending = summary.sections[2].lines;
    expect(pending.where((l) => l.contains('Ceftriaxona')), hasLength(1));
    expect(summary.asText(), contains('Pendientes'));
  });

  testWidgets('handoff screen renders the Figma sections and copy action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const HandoffScreen(hospitalizationId: _episode)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Entrega de turno'), findsOneWidget);
    expect(find.text('Estado actual'), findsOneWidget);
    expect(find.text('Cambios recientes'), findsOneWidget);
    expect(find.text('Pendientes'), findsOneWidget);
    expect(find.text('Copiar resumen'), findsOneWidget);
    // Without the AI summary permission the link is hidden, not redirected.
    expect(find.text('Resúmenes con IA'), findsNothing);
  });

  testWidgets('bitácora filters by profession and shows nursing cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const PatientDetailScreen(hospitalizationId: _episode),
        events: [
          _note('n1', 'Nota de enfermería', 'enfermeria'),
          _note('n2', 'Nota de kinesiología', 'kinesiologia'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Signos vitales'), findsWidgets);
    expect(find.text('Médico tratante'), findsOneWidget);
    expect(find.text('Nota de enfermería'), findsOneWidget);
    expect(find.text('Nota de kinesiología'), findsOneWidget);
    await tester.ensureVisible(find.text('Kinesiología').first);
    await tester.tap(find.text('Kinesiología').first);
    await tester.pumpAndSettle();
    expect(find.text('Nota de enfermería'), findsNothing);
    expect(find.text('Nota de kinesiología'), findsOneWidget);

    await tester.ensureVisible(find.text('Medicamentos'));
    await tester.tap(find.text('Medicamentos'));
    await tester.pumpAndSettle();
    expect(find.text('Horario de medicamentos'), findsOneWidget);
    expect(find.text('Sin registro'), findsOneWidget);

    await tester.ensureVisible(find.text('Nutrición'));
    await tester.tap(find.text('Nutrición'));
    await tester.pumpAndSettle();
    expect(find.text('Balance hídrico'), findsOneWidget);
    expect(find.text('+50 mL'), findsOneWidget);
  });

  test(
    'biometric lock requires a successful check to enable and unlock',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final auth = _FakeAuthenticator();
      final lock = BiometricLockController(auth);
      await lock.load();
      expect(lock.enabled, isFalse);

      auth.accept = false;
      expect(await lock.setEnabled(true), isFalse);
      expect(lock.enabled, isFalse);

      auth.accept = true;
      expect(await lock.setEnabled(true), isTrue);
      expect(lock.locked, isFalse);
      lock.lock();
      expect(lock.locked, isTrue);
      auth.accept = false;
      expect(await lock.unlock(), isFalse);
      expect(lock.locked, isTrue);
      auth.accept = true;
      expect(await lock.unlock(), isTrue);
      expect(lock.locked, isFalse);

      // A cold start with the preference stored begins locked.
      final restarted = BiometricLockController(auth);
      await restarted.load();
      expect(restarted.enabled, isTrue);
      expect(restarted.locked, isTrue);

      auth.available = false;
      final other = BiometricLockController(auth);
      await other.load();
      await other.setEnabled(false);
      expect(await other.setEnabled(true), isFalse);
    },
  );
}
