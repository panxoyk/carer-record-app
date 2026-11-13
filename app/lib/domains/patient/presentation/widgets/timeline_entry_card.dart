import 'package:flutter/material.dart';

import '../../../../core/design_system/clinical_design_system.dart';
import '../../../../core/time/clinical_time.dart';

/// Event card of the bitácora (Figma "Timeline Item"): a colored dot on a
/// vertical rail and a white card with time, category, title and detail.
class TimelineEntryCard extends StatelessWidget {
  const TimelineEntryCard({
    required this.title,
    required this.category,
    required this.date,
    required this.dateOnly,
    this.detail,
    this.author,
    this.isNote = false,
    this.tint,
    this.role,
    this.attachment,
    super.key,
  });

  final String title;
  final String category;
  final String? date;
  final String? detail;
  final String? author;
  final bool dateOnly;
  final bool isNote;

  /// Category color chosen by the author (overrides the type color).
  final ClinicalTint? tint;

  /// Author role shown after the time, e.g. "Enfermería".
  final String? role;

  /// Optional clinical photo shown inside the card.
  final Widget? attachment;

  @override
  Widget build(BuildContext context) {
    final tint = this.tint ?? timelineCategoryTint(category, isNote: isNote);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ClinicalSpacing.page),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned.fill(
            child: CustomPaint(
              painter: _TimelineRailPainter(color: ClinicalColors.separator),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(
              left: ClinicalSpacing.section,
              bottom: ClinicalSpacing.item,
            ),
            child: ClinicalCard(
              radius: ClinicalRadii.event,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                if (date != null)
                                  TextSpan(
                                    text: dateOnly
                                        ? 'Solo fecha · ${date!.split('-').reversed.join('-')}'
                                        : formatClinicalTime(
                                            DateTime.parse(date!),
                                          ),
                                    style: ClinicalTextStyles.mono,
                                  ),
                                if (role != null)
                                  TextSpan(
                                    text: date == null ? role : ' · $role',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: ClinicalColors.secondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: ClinicalSpacing.compact),
                        Flexible(
                          child: ClinicalBadge(
                            label: category,
                            color: tint.background,
                            textColor: tint.color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: ClinicalColors.ink,
                      ),
                    ),
                    if (detail?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        detail!,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: ClinicalColors.secondary,
                        ),
                      ),
                    ],
                    if (attachment != null) ...[
                      const SizedBox(height: 4),
                      attachment!,
                    ],
                    if (isNote) ...[
                      const SizedBox(height: ClinicalSpacing.compact),
                      Text(
                        author == null || author!.trim().isEmpty
                            ? 'Autor no disponible'
                            : 'Registrada por $author',
                        style: const TextStyle(
                          fontSize: 11,
                          color: ClinicalColors.secondary,
                        ),
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
                  padding: const EdgeInsets.only(top: 18),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: tint.color,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(
                          color: ClinicalColors.canvas,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
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

/// Color de cada categoría de la bitácora, alineado con las categorías del
/// diseño (nota → comunicación, observación → signos vitales, etc.).
ClinicalTint timelineCategoryTint(String category, {bool isNote = false}) {
  if (isNote || category == 'Nota de contexto') {
    return ClinicalCategoryColors.communication;
  }
  return switch (category) {
    'Observación' => ClinicalCategoryColors.vitals,
    'Informe' => ClinicalCategoryColors.clinicalNote,
    'Medicación' => ClinicalCategoryColors.pharmacology,
    'Condición' => ClinicalCategoryColors.tens,
    'Procedimiento' => ClinicalCategoryColors.mobility,
    'Alergia' => ClinicalCategoryColors.procedure,
    _ => ClinicalCategoryColors.routine,
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
    const x = ClinicalSpacing.section / 2;
    canvas.drawLine(const Offset(x, 0), Offset(x, size.height), paint);
  }

  @override
  bool shouldRepaint(_TimelineRailPainter oldDelegate) =>
      oldDelegate.color != color;
}
