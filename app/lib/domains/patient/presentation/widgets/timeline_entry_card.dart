import 'package:flutter/material.dart';

import '../../../../core/design_system/clinical_design_system.dart';
import '../../../../core/time/clinical_time.dart';

class TimelineEntryCard extends StatelessWidget {
  const TimelineEntryCard({
    required this.title,
    required this.category,
    required this.date,
    required this.dateOnly,
    this.detail,
    this.author,
    this.isNote = false,
    super.key,
  });

  final String title;
  final String category;
  final String? date;
  final String? detail;
  final String? author;
  final bool dateOnly;
  final bool isNote;

  @override
  Widget build(BuildContext context) {
    final badgeColors = _categoryBadgeColors(category, isNote: isNote);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ClinicalSpacing.page),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _TimelineRailPainter(color: ClinicalColors.separator),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(
              left: ClinicalSpacing.section,
              bottom: ClinicalSpacing.compact,
            ),
            child: ClinicalCard(
              backgroundColor: isNote ? ClinicalColors.softMint : Colors.white,
              padding: const EdgeInsets.all(ClinicalSpacing.card),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: ClinicalSpacing.compact,
                      runSpacing: ClinicalSpacing.compact,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (date != null)
                          Text(
                            dateOnly
                                ? 'Solo fecha · ${date!.split('-').reversed.join('-')}'
                                : formatClinicalTime(DateTime.parse(date!)),
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ClinicalBadge(
                          label: category,
                          color: badgeColors.$1,
                          textColor: badgeColors.$2,
                        ),
                      ],
                    ),
                    const SizedBox(height: ClinicalSpacing.compact),
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    if (detail?.isNotEmpty == true) ...[
                      const SizedBox(height: ClinicalSpacing.compact),
                      Text(detail!),
                    ],
                    if (isNote) ...[
                      const SizedBox(height: ClinicalSpacing.compact),
                      Text(
                        author == null || author!.trim().isEmpty
                            ? 'Autor no disponible'
                            : 'Registrada por $author',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: SizedBox(
              width: ClinicalSpacing.section,
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: ClinicalSpacing.card),
                  child: Icon(
                    isNote ? Icons.sticky_note_2_outlined : Icons.circle,
                    size: isNote ? 20 : ClinicalSpacing.compact,
                    color: ClinicalColors.mintText,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

(Color, Color) _categoryBadgeColors(String category, {required bool isNote}) {
  if (isNote || category == 'Nota de contexto') {
    return (ClinicalColors.softMint, ClinicalColors.mintBadgeText);
  }
  return switch (category) {
    'Observación' => (
      ClinicalColors.softObservation,
      ClinicalColors.observationText,
    ),
    'Informe' => (ClinicalColors.softReport, ClinicalColors.reportText),
    'Medicación' => (
      ClinicalColors.softMedication,
      ClinicalColors.medicationText,
    ),
    'Condición' => (ClinicalColors.softCondition, ClinicalColors.conditionText),
    'Procedimiento' => (
      ClinicalColors.softProcedure,
      ClinicalColors.procedureText,
    ),
    'Alergia' => (ClinicalColors.softAttention, ClinicalColors.ink),
    _ => (ClinicalColors.canvas, ClinicalColors.ink),
  };
}

class _TimelineRailPainter extends CustomPainter {
  const _TimelineRailPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final x = ClinicalSpacing.section / 2;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
  }

  @override
  bool shouldRepaint(_TimelineRailPainter oldDelegate) =>
      oldDelegate.color != color;
}
