import '../design_system/clinical_tokens.dart';

/// Category the professional chooses for each bitácora event (ADR-022).
///
/// `wire` values match the `context_notes.category` check constraint.
enum EventCategory {
  notaClinica('nota_clinica', 'Nota clínica'),
  signosVitales('signos_vitales', 'Signos vitales'),
  procedimiento('procedimiento', 'Procedimiento'),
  farmacologia('farmacologia', 'Farmacología'),
  comunicacion('comunicacion', 'Comunicación'),
  movilidad('movilidad', 'Movilidad'),
  nutricion('nutricion', 'Nutrición'),
  tens('tens', 'TENS'),
  rutina('rutina', 'Rutina');

  const EventCategory(this.wire, this.label);
  final String wire;
  final String label;

  static EventCategory? fromWire(String? value) {
    for (final category in values) {
      if (category.wire == value) return category;
    }
    return null;
  }

  ClinicalTint get tint => switch (this) {
    EventCategory.notaClinica => ClinicalCategoryColors.clinicalNote,
    EventCategory.signosVitales => ClinicalCategoryColors.vitals,
    EventCategory.procedimiento => ClinicalCategoryColors.procedure,
    EventCategory.farmacologia => ClinicalCategoryColors.pharmacology,
    EventCategory.comunicacion => ClinicalCategoryColors.communication,
    EventCategory.movilidad => ClinicalCategoryColors.mobility,
    EventCategory.nutricion => ClinicalCategoryColors.nutrition,
    EventCategory.tens => ClinicalCategoryColors.tens,
    EventCategory.rutina => ClinicalCategoryColors.routine,
  };
}

/// Clinical profession of a member, snapshotted on each note (ADR-022).
enum Profession {
  medicina('medicina', 'Medicina', 'Médico'),
  enfermeria('enfermeria', 'Enfermería', 'Enfermería'),
  tens('tens', 'TENS', 'TENS'),
  kinesiologia('kinesiologia', 'Kinesiología', 'Kinesiología'),
  nutricion('nutricion', 'Nutrición', 'Nutrición'),
  otro('otro', 'Otra profesión', 'Profesional');

  const Profession(this.wire, this.label, this.roleLabel);
  final String wire;

  /// Filter label (estamento), e.g. "Medicina".
  final String label;

  /// Author role shown next to the event time, e.g. "Médico".
  final String roleLabel;

  static Profession? fromWire(String? value) {
    for (final profession in values) {
      if (profession.wire == value) return profession;
    }
    return null;
  }
}

/// Shift containing [time] in the institution's local clock: 08–16, 16–24 or
/// 00–08.
String clinicalShiftLabel(DateTime localTime) {
  final hour = localTime.hour;
  if (hour >= 8 && hour < 16) return '08:00–16:00';
  if (hour >= 16) return '16:00–24:00';
  return '00:00–08:00';
}
