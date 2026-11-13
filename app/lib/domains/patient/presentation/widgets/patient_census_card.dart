import 'package:flutter/material.dart';

import '../../../../core/design_system/clinical_design_system.dart';
import '../../domain/entities/patient.dart';

/// Patient Card del diseño Figma: avatar con iniciales, edad, día de
/// hospitalización, ubicación, estado y servicio, con un borde de color por
/// servicio (o por estado si el censo no informa el servicio).
class PatientCensusCard extends StatelessWidget {
  const PatientCensusCard({
    required this.patient,
    required this.status,
    required this.location,
    required this.onTap,
    this.service,
    this.serviceTint,
    super.key,
  });

  final Patient patient;
  final Widget status;
  final String location;
  final VoidCallback onTap;
  final String? service;
  final ClinicalTint? serviceTint;

  @override
  Widget build(BuildContext context) {
    final tint =
        serviceTint ?? patientStatusTint(patient.hospitalizationStatus);
    final age = patientAge(patient.birthDate);
    final day = hospitalizationDay(patient);
    return ClinicalCard(
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: tint.color, width: 4)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ClinicalAvatar(
                    initials: clinicalInitials(patient.fullName),
                    background: tint.background,
                    foreground: tint.color,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          patient.fullName,
                          style: ClinicalTextStyles.headline,
                        ),
                        if (age != null)
                          Text(
                            '$age años',
                            style: const TextStyle(
                              fontSize: 13,
                              color: ClinicalColors.secondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (day != null) ...[
                    const SizedBox(width: 8),
                    ClinicalBadge(
                      label: 'Día $day',
                      color: ClinicalColors.fillSubtle,
                      textColor: ClinicalColors.secondary,
                    ),
                  ],
                  const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: ClinicalColors.tertiary,
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1),
              ),
              Row(
                children: [
                  const Icon(
                    Icons.bed_outlined,
                    size: 16,
                    color: ClinicalColors.secondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      location,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: ClinicalColors.secondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (patient.hospitalizationStatus == 'admitted')
                Row(
                  children: [
                    status,
                    if (service != null) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: ClinicalBadge(
                          label: service!,
                          color: tint.background,
                          textColor: tint.color,
                        ),
                      ),
                    ],
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: status,
                      ),
                    ),
                    if (service != null) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: ClinicalBadge(
                          label: service!,
                          color: tint.background,
                          textColor: tint.color,
                        ),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Color del estado de la hospitalización (borde, avatar).
ClinicalTint patientStatusTint(String status) => switch (status) {
  'admitted' => const ClinicalTint(
    ClinicalColors.mintText,
    ClinicalColors.softMint,
  ),
  'temporarily_absent' => const ClinicalTint(
    ClinicalColors.attention,
    ClinicalColors.softAttention,
  ),
  'discharged' => const ClinicalTint(
    ClinicalColors.secondary,
    ClinicalColors.fillSubtle,
  ),
  _ => const ClinicalTint(
    ClinicalColors.observationText,
    ClinicalColors.softObservation,
  ),
};

int? patientAge(DateTime? birthDate, {DateTime? now}) {
  if (birthDate == null) return null;
  final today = now ?? DateTime.now();
  final beforeBirthday =
      today.month < birthDate.month ||
      (today.month == birthDate.month && today.day < birthDate.day);
  final age = today.year - birthDate.year - (beforeBirthday ? 1 : 0);
  return age < 0 ? null : age;
}

/// Día de hospitalización (el día de ingreso es el día 1). Solo para episodios
/// abiertos; un episodio cerrado no suma días.
int? hospitalizationDay(Patient patient, {DateTime? now}) {
  if (patient.hospitalizationStatus != 'admitted' &&
      patient.hospitalizationStatus != 'temporarily_absent') {
    return null;
  }
  final today = (now ?? DateTime.now()).toUtc();
  final admitted = patient.admittedAt.toUtc();
  final days =
      DateTime.utc(today.year, today.month, today.day)
          .difference(DateTime.utc(admitted.year, admitted.month, admitted.day))
          .inDays +
      1;
  return days < 1 ? null : days;
}

/// Color por servicio, en el orden de las píldoras (paleta del diseño).
ClinicalTint? serviceTint(int index) {
  if (index < 0) return null;
  const palette = [
    ClinicalCategoryColors.clinicalNote,
    ClinicalCategoryColors.procedure,
    ClinicalCategoryColors.pharmacology,
    ClinicalCategoryColors.mobility,
    ClinicalCategoryColors.vitals,
    ClinicalCategoryColors.tens,
  ];
  return palette[index % palette.length];
}
