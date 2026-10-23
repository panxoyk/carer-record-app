import 'package:flutter/material.dart';

/// Semantic color values shared by clinical presentation.
abstract final class ClinicalColors {
  static const mint = Color(0xff4eddb3);
  static const mintDark = Color(0xff2ab892);
  static const mintText = Color(0xff087f5b);
  static const softMint = Color(0xffe7faf4);
  static const mintBadgeText = Color(0xff006044);
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
  static const pill = 999.0;
}

abstract final class ClinicalTextStyles {
  static const pageTitle = TextStyle(
    fontSize: 28,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: ClinicalColors.ink,
  );
  static const sectionTitle = TextStyle(
    fontSize: 18,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: ClinicalColors.ink,
  );
}
