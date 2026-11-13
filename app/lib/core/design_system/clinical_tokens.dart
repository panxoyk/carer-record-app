import 'package:flutter/material.dart';

/// Semantic color values shared by clinical presentation.
///
/// Values follow the Carer-Record Figma v2 design system (`CR` tokens): a
/// contemporary mint brand color used sparingly over iOS-like neutrals.
abstract final class ClinicalColors {
  static const mint = Color(0xff4eddb3);
  static const mintDark = Color(0xff2ab892);
  static const mintText = Color(0xff087f5b);
  static const softMint = Color(0xffe7faf4);
  static const mintBadgeText = Color(0xff006044);

  /// Text drawn over mint surfaces (primary buttons, avatars).
  static const onMint = Color(0xff0d3d2a);
  static const mintGradientStart = Color(0xff72edd2);
  static const mintGradientEnd = Color(0xff29b88f);

  static const attention = Color(0xff8a5a00);
  static const softAttention = Color(0xfffff4d6);
  static const observationText = Color(0xff0d47a1);
  static const softObservation = Color(0xffe3f2fd);
  static const reportText = Color(0xff4a148c);
  static const softReport = Color(0xfff3e5f5);
  static const medicationText = Color(0xff8a3800);
  static const softMedication = Color(0xffffe8d6);
  static const conditionText = Color(0xff283593);
  static const softCondition = Color(0xffe8eaf6);
  static const procedureText = Color(0xff006064);
  static const softProcedure = Color(0xffe0f7fa);

  static const ink = Color(0xff1c1c1e);
  static const canvas = Color(0xfff2f2f7);
  static const secondary = Color(0xff6e6e73);
  static const tertiary = Color(0xffaeaeb2);
  static const separator = Color(0x1f3c3c43);
  static const divider = Color(0xffd1d1d6);
  static const destructive = Color(0xffff3b30);

  /// iOS system accents used by the design for links and categories.
  static const blue = Color(0xff007aff);
  static const orange = Color(0xffff9500);
  static const purple = Color(0xffaf52de);
  static const teal = Color(0xff007575);

  /// Neutral fill used by search fields, inactive chips and round buttons.
  static const fill = Color(0x1f767680);
  static const fillSubtle = Color(0x14767680);
}

/// Category tint: a strong color for text/dots and a soft opaque background
/// (the Figma 12 % tint pre-blended over white).
@immutable
class ClinicalTint {
  const ClinicalTint(this.color, this.background);
  final Color color;
  final Color background;
}

/// Category colors from the Figma design (`CATEGORIES`).
abstract final class ClinicalCategoryColors {
  // Text colors are darkened from the Figma hues so badge text keeps a 4.5:1
  // contrast over its 12 % background.
  static const routine = ClinicalTint(Color(0xff5a5a5f), Color(0xffeeeeee));
  static const mobility = ClinicalTint(Color(0xff7a2ca3), Color(0xfff5eafb));
  static const clinicalNote = ClinicalTint(
    Color(0xff0055b3),
    Color(0xffe0efff),
  );
  static const pharmacology = ClinicalTint(
    Color(0xff8a4b00),
    Color(0xfffff2e0),
  );
  static const procedure = ClinicalTint(Color(0xffb00012), Color(0xffffe7e6));
  static const vitals = ClinicalTint(Color(0xff006060), Color(0xffe0eeee));
  static const tens = ClinicalTint(Color(0xff3d4a94), Color(0xffe9ebf4));
  static const nutrition = ClinicalTint(Color(0xff445e1c), Color(0xffeaeee5));
  static const communication = ClinicalTint(
    Color(0xff006044),
    Color(0xffe4faf4),
  );
}

/// Semantic spacing and shape values for shared clinical presentation.
abstract final class ClinicalSpacing {
  static const page = 20.0;
  static const section = 24.0;
  static const card = 16.0;
  static const compact = 8.0;
  static const item = 12.0;
}

abstract final class ClinicalRadii {
  static const card = 16.0;
  static const control = 12.0;
  static const event = 14.0;
  static const button = 18.0;
  static const large = 20.0;
  static const pill = 999.0;
}

abstract final class ClinicalShadows {
  static const card = [
    BoxShadow(color: Color(0x0f000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
  static const raised = [
    BoxShadow(color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 4)),
  ];
}

abstract final class ClinicalTextStyles {
  static const largeTitle = TextStyle(
    fontSize: 34,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: ClinicalColors.ink,
  );
  static const pageTitle = TextStyle(
    fontSize: 28,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: ClinicalColors.ink,
  );
  static const sectionTitle = TextStyle(
    fontSize: 20,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: ClinicalColors.ink,
  );
  static const headline = TextStyle(
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: ClinicalColors.ink,
  );
  static const body = TextStyle(
    fontSize: 15,
    height: 1.4,
    color: ClinicalColors.ink,
  );
  static const subhead = TextStyle(
    fontSize: 13,
    height: 1.4,
    color: ClinicalColors.secondary,
  );
  static const footnote = TextStyle(
    fontSize: 12,
    height: 1.3,
    color: ClinicalColors.secondary,
  );
  static const mono = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    fontFamily: 'monospace',
    color: ClinicalColors.tertiary,
  );
}
