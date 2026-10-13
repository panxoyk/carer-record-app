import 'package:carer_record_app/core/design_system/clinical_design_system.dart';
import 'package:carer_record_app/core/design_system/clinical_page_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('fields inherit the shared input styling from the theme', (
    tester,
  ) async {
    late BuildContext probeContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: ClinicalTheme.build(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              probeContext = context;
              return const TextField(
                decoration: InputDecoration(labelText: 'Campo'),
              );
            },
          ),
        ),
      ),
    );

    final border = Theme.of(probeContext).inputDecorationTheme.enabledBorder;
    expect(border, isA<OutlineInputBorder>());
    final outline = border! as OutlineInputBorder;
    expect(outline.borderSide.color, ClinicalColors.separator);
    expect(outline.borderRadius, BorderRadius.circular(12));
    expect(
      Theme.of(probeContext).inputDecorationTheme.floatingLabelStyle?.color,
      ClinicalColors.mintText,
    );

    final decoration = clinicalInputDecoration(labelText: 'Campo');
    expect(decoration.labelText, 'Campo');
    expect(decoration.filled, isNull);
    expect(decoration.border, isNull);
    expect(decoration.fillColor, isNull);
  });

  testWidgets('theme exposes semantic hierarchy and shared page components', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ClinicalTheme.build(),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(ClinicalSpacing.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClinicalPageTitle('Usuarios', subtitle: 'Administración'),
                ClinicalContentCard(child: Text('Contenido')),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Usuarios'), findsOneWidget);
    expect(find.text('Administración'), findsOneWidget);
    expect(find.text('Contenido'), findsOneWidget);
    final context = tester.element(find.text('Usuarios'));
    expect(
      Theme.of(context).textTheme.headlineMedium?.fontSize,
      ClinicalTextStyles.pageTitle.fontSize,
    );
    expect(Theme.of(context).dividerTheme.color, ClinicalColors.divider);
    final buttonStyle = Theme.of(context).filledButtonTheme.style!;
    expect(buttonStyle.foregroundColor!.resolve(const {}), ClinicalColors.ink);
    expect(
      buttonStyle.backgroundColor!.resolve(const {}),
      ClinicalColors.mintDark,
    );
    expect(
      Theme.of(
        context,
      ).textButtonTheme.style!.foregroundColor!.resolve(const {}),
      ClinicalColors.mintText,
    );
  });
}
