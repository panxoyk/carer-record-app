import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'clinical_tokens.dart';

/// Tokens visuales compartidos por las pantallas clínicas.
export 'clinical_tokens.dart'
    show ClinicalColors, ClinicalRadii, ClinicalSpacing, ClinicalTextStyles;

abstract final class ClinicalTheme {
  static ThemeData build() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: ClinicalColors.mint,
      brightness: Brightness.light,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: ClinicalColors.canvas,
    textTheme: const TextTheme(
      headlineMedium: ClinicalTextStyles.pageTitle,
      titleLarge: ClinicalTextStyles.sectionTitle,
      bodyLarge: TextStyle(color: ClinicalColors.ink),
      bodyMedium: TextStyle(color: ClinicalColors.secondary),
      labelLarge: TextStyle(fontWeight: FontWeight.w600),
    ),
    dividerTheme: const DividerThemeData(
      color: ClinicalColors.divider,
      thickness: 1,
      space: 1,
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: ClinicalColors.canvas,
      indicatorColor: ClinicalColors.softMint,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ClinicalColors.mintDark,
        foregroundColor: ClinicalColors.ink,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ClinicalRadii.control),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: ClinicalColors.mintText),
    ),
    inputDecorationTheme: _inputTheme,
  );
}

final InputDecorationTheme _inputTheme = InputDecorationTheme(
  filled: true,
  fillColor: Colors.white,
  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  border: _inputBorder(ClinicalColors.separator),
  enabledBorder: _inputBorder(ClinicalColors.separator),
  focusedBorder: _inputBorder(ClinicalColors.mintDark, width: 1.6),
  errorBorder: _inputBorder(ClinicalColors.destructive),
  focusedErrorBorder: _inputBorder(ClinicalColors.destructive, width: 1.6),
  labelStyle: const TextStyle(color: ClinicalColors.secondary),
  floatingLabelStyle: const TextStyle(color: ClinicalColors.mintText),
  errorStyle: const TextStyle(color: ClinicalColors.destructive),
);

OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: width),
    );

/// Decoración común de los campos de entrada. Los bordes, el relleno y los
/// estados viven en el tema; aquí solo se declara el contenido del campo.
InputDecoration clinicalInputDecoration({
  String? labelText,
  String? hintText,
  String? helperText,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) => InputDecoration(
  labelText: labelText,
  hintText: hintText,
  helperText: helperText,
  prefixIcon: prefixIcon,
  suffixIcon: suffixIcon,
);

class ClinicalCard extends StatelessWidget {
  const ClinicalCard({
    required this.child,
    this.padding,
    this.radius = 16,
    this.backgroundColor = Colors.white,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) => Material(
    color: backgroundColor,
    clipBehavior: Clip.antiAlias,
    borderRadius: BorderRadius.circular(radius),
    child: padding == null ? child : Padding(padding: padding!, child: child),
  );
}

class ClinicalBadge extends StatelessWidget {
  const ClinicalBadge({
    required this.label,
    required this.color,
    required this.textColor,
    this.icon,
    super.key,
  });
  final String label;
  final Color color;
  final Color textColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: ClinicalSpacing.compact,
      vertical: ClinicalSpacing.compact,
    ),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(ClinicalRadii.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: ClinicalSpacing.compact),
        ],
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: textColor, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class ClinicalSectionTitle extends StatelessWidget {
  const ClinicalSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        letterSpacing: .7,
        fontWeight: FontWeight.w700,
        color: ClinicalColors.secondary,
      ),
    ),
  );
}

class ClinicalProfileCard extends StatelessWidget {
  const ClinicalProfileCard({
    required this.initials,
    required this.name,
    required this.subtitle,
    this.status = 'Activo',
    super.key,
  });

  final String initials;
  final String name;
  final String subtitle;
  final String status;

  @override
  Widget build(BuildContext context) => ClinicalCard(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: ClinicalColors.softMint,
          foregroundColor: ClinicalColors.mintDark,
          child: Text(
            initials,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: ClinicalColors.ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 14,
                  color: ClinicalColors.secondary,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: ClinicalColors.softMint,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            status,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: ClinicalColors.mintDark,
            ),
          ),
        ),
      ],
    ),
  );
}

class ClinicalSettingsSection extends StatelessWidget {
  const ClinicalSettingsSection({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ClinicalSectionTitle(title),
      ClinicalCard(child: Column(children: children)),
    ],
  );
}

class ClinicalSettingsRow extends StatelessWidget {
  const ClinicalSettingsRow({
    required this.label,
    required this.icon,
    this.value,
    this.destructive = false,
    this.isLast = false,
    this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final String? value;
  final bool destructive;
  final bool isLast;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? ClinicalColors.destructive
        : ClinicalColors.mintDark;
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: destructive ? color : ClinicalColors.ink,
                    ),
                  ),
                ),
                if (value != null)
                  Flexible(
                    child: Text(
                      value!,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 14,
                        color: ClinicalColors.secondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (!isLast)
          const Divider(height: 1, indent: 47, color: ClinicalColors.separator),
      ],
    );
  }
}

class ClinicalBottomNavigation extends StatelessWidget {
  const ClinicalBottomNavigation({required this.selectedIndex, super.key});

  final int selectedIndex;

  @override
  Widget build(BuildContext context) => NavigationBar(
    selectedIndex: selectedIndex,
    destinations: const [
      NavigationDestination(
        icon: Icon(Icons.people_outline_rounded),
        selectedIcon: Icon(Icons.people_rounded),
        label: 'Pacientes',
      ),
      NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings_rounded),
        label: 'Ajustes',
      ),
    ],
    onDestinationSelected: (index) {
      if (index == selectedIndex) return;
      context.go(index == 0 ? '/patients' : '/settings');
    },
  );
}

AppBar clinicalBackAppBar(
  BuildContext context, {
  required String title,
  String fallbackLocation = '/patients',
  String tooltip = 'Volver',
  List<Widget>? actions,
}) => clinicalAppBar(
  title: title,
  leadingWidth: 56,
  leading: IconButton(
    tooltip: tooltip,
    onPressed: () =>
        context.canPop() ? context.pop() : context.go(fallbackLocation),
    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
  ),
  actions: actions,
);

AppBar clinicalAppBar({
  required String title,
  double? leadingWidth,
  Widget? leading,
  List<Widget>? actions,
}) => AppBar(
  backgroundColor: ClinicalColors.canvas,
  surfaceTintColor: ClinicalColors.canvas,
  shadowColor: Colors.transparent,
  elevation: 0,
  scrolledUnderElevation: 0,
  title: Text(
    title,
    style: const TextStyle(
      fontWeight: FontWeight.w700,
      color: ClinicalColors.ink,
    ),
  ),
  leadingWidth: leadingWidth,
  leading: leading,
  actions: actions,
);
