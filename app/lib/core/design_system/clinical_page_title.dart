import 'package:flutter/material.dart';

import 'clinical_design_system.dart';

/// Consistent top-level heading for a page's scrollable content.
class ClinicalPageTitle extends StatelessWidget {
  const ClinicalPageTitle(this.title, {this.subtitle, super.key});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: ClinicalSpacing.section),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        if (subtitle != null) ...[
          const SizedBox(height: ClinicalSpacing.compact),
          Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    ),
  );
}

/// Shared white card surface; use semantic padding rather than local values.
class ClinicalContentCard extends StatelessWidget {
  const ClinicalContentCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => ClinicalCard(
    padding: const EdgeInsets.all(ClinicalSpacing.card),
    child: child,
  );
}
