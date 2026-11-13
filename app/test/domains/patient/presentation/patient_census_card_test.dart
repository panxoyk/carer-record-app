import 'package:carer_record_app/core/design_system/clinical_design_system.dart';
import 'package:carer_record_app/domains/patient/domain/entities/patient.dart';
import 'package:carer_record_app/domains/patient/presentation/widgets/patient_census_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final patient = Patient(
    organizationId: 'org',
    hospitalizationId: 'episode',
    patientId: 'patient',
    hospitalizationStatus: 'admitted',
    admittedAt: DateTime.utc(2026),
    dischargedAt: null,
    unitId: 'unit',
    bedLabel: '12',
    givenName: 'Ana',
    familyName: 'Prueba',
    birthDate: null,
  );

  testWidgets(
    'admitted dot stays beside long service at narrow width and scale',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: PatientCensusCard(
              patient: patient,
              status: Semantics(
                label: 'Hospitalización activa',
                child: const ExcludeSemantics(
                  child: SizedBox.square(
                    dimension: 7,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: ClinicalColors.mintDark,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
              location: 'Cama 12',
              service: 'Cuidados intermedios',
              onTap: () {},
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Hospitalización en curso'), findsNothing);
      final activeStatus = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Hospitalización activa',
      );
      expect(activeStatus, findsOneWidget);
      expect(
        tester.getSemantics(activeStatus).label,
        contains('Hospitalización activa'),
      );

      final dot = find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color ==
                ClinicalColors.mintDark,
      );
      final badgeText = find.text('Cuidados intermedios');
      final badge = find.ancestor(
        of: badgeText,
        matching: find.byType(ClinicalBadge),
      );
      final statusRow = find
          .ancestor(of: dot, matching: find.byType(Row))
          .first;
      expect(dot, findsOneWidget);
      expect(badgeText, findsOneWidget);
      expect(badge, findsOneWidget);
      final dotRect = tester.getRect(dot);
      final badgeRect = tester.getRect(badge);
      expect(
        (dotRect.left - tester.getRect(statusRow).left).abs(),
        lessThan(1),
      );
      expect(dotRect.left, lessThan(badgeRect.left));
      expect((badgeRect.left - dotRect.right - 6).abs(), lessThan(1));
      semantics.dispose();
    },
  );

  testWidgets('non-admitted status badge remains visible', (tester) async {
    final discharged = Patient(
      organizationId: 'org',
      hospitalizationId: 'episode',
      patientId: 'patient',
      hospitalizationStatus: 'discharged',
      admittedAt: DateTime.utc(2026),
      dischargedAt: DateTime.utc(2026, 2),
      unitId: 'unit',
      bedLabel: '12',
      givenName: 'Ana',
      familyName: 'Prueba',
      birthDate: null,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PatientCensusCard(
            patient: discharged,
            status: const ClinicalBadge(
              label: 'Solo lectura',
              color: ClinicalColors.fillSubtle,
              textColor: ClinicalColors.secondary,
            ),
            location: 'Cama 12',
            onTap: () {},
          ),
        ),
      ),
    );
    expect(find.text('Solo lectura'), findsOneWidget);
  });
}
