import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../navigation/current_hospitalization.dart';
import 'clinical_tokens.dart';

/// Tokens visuales compartidos por las pantallas clínicas.
export 'clinical_tokens.dart'
    show
        ClinicalCategoryColors,
        ClinicalColors,
        ClinicalRadii,
        ClinicalShadows,
        ClinicalSpacing,
        ClinicalTextStyles,
        ClinicalTint;

abstract final class ClinicalTheme {
  static ThemeData build() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: ClinicalColors.mint,
      brightness: Brightness.light,
      primary: ClinicalColors.mintDark,
      onPrimary: ClinicalColors.onMint,
      surface: Colors.white,
      error: ClinicalColors.destructive,
    ),
    scaffoldBackgroundColor: ClinicalColors.canvas,
    splashFactory: InkSparkle.splashFactory,
    textTheme: const TextTheme(
      displaySmall: ClinicalTextStyles.largeTitle,
      headlineMedium: ClinicalTextStyles.pageTitle,
      titleLarge: ClinicalTextStyles.sectionTitle,
      titleMedium: ClinicalTextStyles.headline,
      bodyLarge: ClinicalTextStyles.body,
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.4,
        color: ClinicalColors.secondary,
      ),
      bodySmall: ClinicalTextStyles.footnote,
      labelLarge: TextStyle(fontWeight: FontWeight.w600),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: ClinicalColors.secondary,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: ClinicalColors.canvas,
      surfaceTintColor: ClinicalColors.canvas,
      foregroundColor: ClinicalColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: ClinicalTextStyles.headline,
    ),
    dividerTheme: const DividerThemeData(
      color: ClinicalColors.separator,
      thickness: 1,
      space: 1,
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(ClinicalRadii.card)),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: ClinicalColors.mintDark,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(64, 52)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 24),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? const Color(0x474eddb3)
              : ClinicalColors.mint,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? const Color(0x731c1c1e)
              : ClinicalColors.onMint,
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(ClinicalRadii.button),
            ),
          ),
        ),
        backgroundBuilder: (context, states, child) {
          if (states.contains(WidgetState.disabled)) return child!;
          return DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-0.4, -1),
                end: Alignment(0.4, 1),
                colors: [
                  ClinicalColors.mintGradientStart,
                  ClinicalColors.mintGradientEnd,
                ],
              ),
            ),
            child: child,
          );
        },
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        backgroundColor: ClinicalColors.fillSubtle,
        foregroundColor: ClinicalColors.ink,
        side: BorderSide.none,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(ClinicalRadii.card)),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ClinicalColors.blue,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : ClinicalColors.fill,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? ClinicalColors.ink
              : ClinicalColors.secondary,
        ),
        iconColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? ClinicalColors.ink
              : ClinicalColors.secondary,
        ),
        side: const WidgetStatePropertyAll(
          BorderSide(color: Colors.transparent, width: 3),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
      ),
      selectedIcon: const SizedBox.shrink(),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: ClinicalColors.fillSubtle,
      selectedColor: ClinicalColors.ink,
      side: BorderSide.none,
      shape: StadiumBorder(),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: ClinicalColors.secondary,
      ),
      secondaryLabelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: Colors.white,
      ),
      checkmarkColor: Colors.white,
      showCheckmark: false,
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? ClinicalColors.mint : null,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? ClinicalColors.mintDark
            : null,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      showDragHandle: false,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(ClinicalRadii.large)),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      titleTextStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: ClinicalColors.ink,
      ),
      subtitleTextStyle: TextStyle(
        fontSize: 14,
        color: ClinicalColors.secondary,
      ),
      iconColor: ClinicalColors.tertiary,
    ),
    inputDecorationTheme: _inputTheme,
  );
}

final InputDecorationTheme _inputTheme = InputDecorationTheme(
  filled: true,
  fillColor: Colors.white,
  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
  border: _inputBorder(ClinicalColors.separator),
  enabledBorder: _inputBorder(ClinicalColors.separator),
  focusedBorder: _inputBorder(ClinicalColors.mint, width: 1.5),
  errorBorder: _inputBorder(ClinicalColors.destructive),
  focusedErrorBorder: _inputBorder(ClinicalColors.destructive, width: 1.5),
  labelStyle: const TextStyle(color: ClinicalColors.secondary),
  floatingLabelStyle: const TextStyle(color: ClinicalColors.mintText),
  hintStyle: const TextStyle(color: ClinicalColors.tertiary),
  errorStyle: const TextStyle(color: ClinicalColors.destructive),
);

OutlineInputBorder _inputBorder(Color color, {double width = 1.5}) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(ClinicalRadii.control),
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
    this.radius = ClinicalRadii.card,
    this.backgroundColor = Colors.white,
    this.elevated = true,
    this.border,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final Color backgroundColor;
  final bool elevated;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      boxShadow: elevated ? ClinicalShadows.card : null,
      border: border,
    ),
    child: Material(
      color: backgroundColor,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(radius),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    ),
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
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(ClinicalRadii.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
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
        fontSize: 13,
        letterSpacing: .5,
        fontWeight: FontWeight.w500,
        color: ClinicalColors.secondary,
      ),
    ),
  );
}

/// Título grande estilo iOS que encabeza las pantallas principales.
class ClinicalLargeTitle extends StatelessWidget {
  const ClinicalLargeTitle(
    this.title, {
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 4, 20, 12),
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: ClinicalTextStyles.largeTitle),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 15,
                    color: ClinicalColors.secondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Campo de búsqueda en píldora gris, como el Search Field de iOS.
class ClinicalSearchField extends StatelessWidget {
  const ClinicalSearchField({
    required this.controller,
    required this.hintText,
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    textInputAction: TextInputAction.search,
    style: const TextStyle(fontSize: 16, color: ClinicalColors.ink),
    decoration: InputDecoration(
      hintText: hintText,
      isDense: true,
      fillColor: ClinicalColors.fill,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      prefixIcon: const Icon(
        Icons.search_rounded,
        size: 20,
        color: ClinicalColors.tertiary,
      ),
      border: _pillBorder,
      enabledBorder: _pillBorder,
      focusedBorder: _pillBorder,
    ),
  );
}

const _pillBorder = OutlineInputBorder(
  borderRadius: BorderRadius.all(Radius.circular(ClinicalRadii.pill)),
  borderSide: BorderSide.none,
);

/// Píldora de filtro: activa en tinta oscura, inactiva en gris translúcido.
class ClinicalFilterPill extends StatelessWidget {
  const ClinicalFilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.leadingDot,
    this.trailing,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? leadingDot;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? ClinicalColors.ink : ClinicalColors.fillSubtle,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leadingDot != null && selected) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: leadingDot,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : ClinicalColors.secondary,
                ),
              ),
              if (trailing != null && !selected) ...[
                const SizedBox(width: 5),
                Text(
                  trailing!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: ClinicalColors.tertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// Fila desplazable horizontal de píldoras de filtro.
class ClinicalPillRow extends StatelessWidget {
  const ClinicalPillRow({required this.children, super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          children[i],
        ],
      ],
    ),
  );
}

/// Avatar circular con iniciales.
class ClinicalAvatar extends StatelessWidget {
  const ClinicalAvatar({
    required this.initials,
    this.size = 40,
    this.background = ClinicalColors.mint,
    this.foreground = ClinicalColors.onMint,
    super.key,
  });

  final String initials;
  final double size;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.32,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    ),
  );
}

/// Iniciales (máximo dos) de un nombre visible.
String clinicalInitials(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((part) => part.isNotEmpty)
    .take(2)
    .map((part) => part[0].toUpperCase())
    .join();

/// Píldora de contexto del paciente activo (punto mint + etiqueta).
class ClinicalPatientContextPill extends StatelessWidget {
  const ClinicalPatientContextPill({required this.label, super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: ClinicalColors.softMint,
        borderRadius: BorderRadius.circular(ClinicalRadii.pill),
        border: Border.all(color: const Color(0x4d4eddb3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: ClinicalColors.mintDark,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: ClinicalColors.mintText,
              ),
            ),
          ),
        ],
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
        ClinicalAvatar(
          initials: initials,
          size: 56,
          background: ClinicalColors.softMint,
          foreground: ClinicalColors.mintDark,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: ClinicalTextStyles.headline),
              const SizedBox(height: 2),
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
        ClinicalBadge(
          label: status,
          color: ClinicalColors.softMint,
          textColor: ClinicalColors.mintDark,
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
      ClinicalCard(
        radius: ClinicalRadii.large,
        elevated: false,
        border: Border.all(color: ClinicalColors.separator),
        child: Column(children: children),
      ),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: destructive
                        ? const Color(0x1aff3b30)
                        : ClinicalColors.softMint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 17, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      color: destructive ? color : ClinicalColors.ink,
                    ),
                  ),
                ),
                if (value != null)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        value!,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontSize: 15,
                          color: ClinicalColors.secondary,
                        ),
                      ),
                    ),
                  ),
                if (onTap != null && !destructive)
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: ClinicalColors.tertiary,
                  ),
              ],
            ),
          ),
        ),
        if (!isLast)
          const Divider(height: 1, indent: 58, color: ClinicalColors.separator),
      ],
    );
  }
}

/// Destinos de la barra inferior del diseño Figma.
enum ClinicalTab { cases, timeline, handoff, settings }

/// Barra inferior flotante: píldora translúcida con las pestañas y, separado,
/// un círculo mint con micrófono para registrar un evento del paciente actual.
class ClinicalBottomNavigation extends ConsumerWidget {
  const ClinicalBottomNavigation({
    required this.current,
    this.onRecord,
    super.key,
  });

  final ClinicalTab current;

  /// Abre el registro de un evento; si es nulo, el botón no se muestra.
  final VoidCallback? onRecord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hospitalizationId = ref.watch(currentHospitalizationProvider);
    String? locationFor(ClinicalTab tab) => switch (tab) {
      ClinicalTab.cases => '/patients',
      ClinicalTab.settings => '/settings',
      ClinicalTab.timeline =>
        hospitalizationId == null
            ? null
            : '/hospitalizations/$hospitalizationId',
      ClinicalTab.handoff =>
        hospitalizationId == null
            ? null
            : '/hospitalizations/$hospitalizationId/handoff',
    };
    // La barra conserva su altura aunque el texto del sistema sea grande.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Center(
                  // Sin heightFactor, Center ocuparía toda la altura del slot
                  // y la barra interceptaría los toques de toda la pantalla.
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: onRecord == null ? 360 : double.infinity,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .92),
                        borderRadius: BorderRadius.circular(ClinicalRadii.pill),
                        border: Border.all(
                          color: const Color(0x14000000),
                          width: .5,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1f000000),
                            blurRadius: 40,
                            offset: Offset(0, 10),
                          ),
                          BoxShadow(
                            color: Color(0x0f000000),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          for (final tab in ClinicalTab.values)
                            Expanded(
                              child: _TabItem(
                                tab: tab,
                                active: tab == current,
                                onTap: locationFor(tab) == null
                                    ? null
                                    : () {
                                        if (tab == current) return;
                                        final target = locationFor(tab)!;
                                        tab == ClinicalTab.cases ||
                                                tab == ClinicalTab.settings
                                            ? context.go(target)
                                            : context.push(target);
                                      },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (onRecord != null) ...[
                const SizedBox(width: 16),
                _RecordButton(onPressed: onRecord!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.tab, required this.active, this.onTap});
  final ClinicalTab tab;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (label, icon, activeIcon) = switch (tab) {
      ClinicalTab.cases => ('Casos', Icons.home_outlined, Icons.home_rounded),
      ClinicalTab.timeline => (
        'Bitácora',
        Icons.article_outlined,
        Icons.article_rounded,
      ),
      ClinicalTab.handoff => (
        'Entrega',
        Icons.assignment_outlined,
        Icons.assignment_rounded,
      ),
      ClinicalTab.settings => (
        'Ajustes',
        Icons.settings_outlined,
        Icons.settings_rounded,
      ),
    };
    final enabled = onTap != null;
    final color = active
        ? ClinicalColors.mintDark
        : enabled
        ? ClinicalColors.tertiary
        : ClinicalColors.tertiary.withValues(alpha: .45);
    return Semantics(
      button: true,
      selected: active,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(40),
            boxShadow: active
                ? const [
                    BoxShadow(
                      color: Color(0x17000000),
                      blurRadius: 6,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active ? activeIcon : icon,
                size: 22,
                color: active ? ClinicalColors.mint : color,
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Registrar evento',
    child: Semantics(
      button: true,
      label: 'Registrar evento',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 58,
          height: 58,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment(-0.4, -1),
              end: Alignment(0.4, 1),
              colors: [
                ClinicalColors.mintGradientStart,
                ClinicalColors.mintGradientEnd,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x942ab892),
                blurRadius: 20,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.mic_rounded, color: Colors.white, size: 26),
        ),
      ),
    ),
  );
}

/// Botón circular gris de navegación (atrás / acciones) estilo iOS 26.
class ClinicalRoundIconButton extends StatelessWidget {
  const ClinicalRoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      backgroundColor: ClinicalColors.fill,
      foregroundColor: ClinicalColors.ink,
      fixedSize: const Size.square(36),
      minimumSize: const Size.square(36),
      padding: EdgeInsets.zero,
    ),
    icon: Icon(icon, size: 18),
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
  leadingWidth: 60,
  leading: Center(
    child: ClinicalRoundIconButton(
      tooltip: tooltip,
      onPressed: () =>
          context.canPop() ? context.pop() : context.go(fallbackLocation),
      icon: Icons.arrow_back_ios_new_rounded,
    ),
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
  centerTitle: true,
  title: Text(title, style: ClinicalTextStyles.headline),
  leadingWidth: leadingWidth,
  leading: leading,
  actions: actions == null
      ? null
      : [...actions, const SizedBox(width: ClinicalSpacing.compact)],
);
