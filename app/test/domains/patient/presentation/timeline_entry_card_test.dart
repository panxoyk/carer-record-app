import 'package:carer_record_app/core/design_system/clinical_design_system.dart';
import 'package:carer_record_app/domains/patient/presentation/widgets/timeline_entry_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({required List<Widget> cards, double textScale = 1}) =>
    MaterialApp(
      theme: ClinicalTheme.build(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(body: ListView(children: cards)),
    );

TimelineEntryCard _card({required String title, bool isNote = false}) =>
    TimelineEntryCard(
      title: title,
      category: isNote ? 'Nota de contexto' : 'Informe',
      date: '2026-10-23T14:35:00Z',
      dateOnly: false,
      detail: 'Detalle del evento',
      author: isNote ? 'Autora de prueba' : null,
      isNote: isNote,
    );

double _luminance(Color color) {
  double linear(int channel) {
    final value = channel / 255;
    return value <= .04045
        ? value / 12.92
        : ((value + .055) / 1.055) * ((value + .055) / 1.055);
  }

  return .2126 * linear((color.r * 255).round()) +
      .7152 * linear((color.g * 255).round()) +
      .0722 * linear((color.b * 255).round());
}

void _expectAccessible(ClinicalBadge badge) {
  final foreground = _luminance(badge.textColor);
  final background = _luminance(badge.color);
  final ratio =
      (foreground > background ? foreground + .05 : background + .05) /
      ((foreground > background ? background : foreground) + .05);
  expect(ratio, greaterThanOrEqualTo(4.5), reason: badge.label);
}

void main() {
  testWidgets('short and long entries use the available card width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      _host(
        cards: [
          _card(title: 'Corto'),
          _card(title: 'Largo ' * 120),
        ],
      ),
    );

    final cards = find.byType(ClinicalCard);
    final firstSize = tester.getSize(cards.at(0));
    final secondSize = tester.getSize(cards.at(1));
    expect(firstSize.width, secondSize.width);
    expect(
      firstSize.width,
      320 - ClinicalSpacing.page * 2 - ClinicalSpacing.section,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'category is a badge and date, author, and date-only remain visible',
    (tester) async {
      await tester.pumpWidget(
        _host(
          cards: [
            _card(title: 'Nota registrada', isNote: true),
            const TimelineEntryCard(
              title: 'Registro con fecha',
              category: 'Observación',
              date: '2026-10-23',
              dateOnly: true,
            ),
          ],
        ),
      );

      expect(find.byType(ClinicalBadge), findsNWidgets(2));
      expect(find.text('Nota de contexto'), findsOneWidget);
      expect(find.text('Observación'), findsOneWidget);
      expect(find.text('Registrada por Autora de prueba'), findsOneWidget);
      expect(find.text('Solo fecha · 23-10-2026'), findsOneWidget);
      expect(find.text('11:35'), findsOneWidget);
    },
  );

  testWidgets(
    'category badges use distinct WCAG AA foreground and background colors',
    (tester) async {
      const categories = [
        'Observación',
        'Informe',
        'Medicación',
        'Condición',
        'Procedimiento',
        'Alergia',
        'Nota de contexto',
        'Otro',
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: ClinicalTheme.build(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  for (final category in categories)
                    TimelineEntryCard(
                      title: 'Evento',
                      category: category,
                      date: null,
                      dateOnly: false,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      final badges = tester.widgetList<ClinicalBadge>(
        find.byType(ClinicalBadge),
      );
      for (final badge in badges) {
        _expectAccessible(badge);
      }
      expect(badges.map((badge) => badge.color).toSet(), hasLength(8));
    },
  );

  testWidgets('long note content fits 320px at 200 percent text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      _host(
        textScale: 2,
        cards: [
          TimelineEntryCard(
            title: 'Título clínico largo ' * 12,
            category: 'Nota de contexto',
            date: '2026-10-23T14:35:00Z',
            dateOnly: false,
            detail: 'Contenido clínico extenso ' * 30,
            author: 'Autora con nombre largo para probar el ancho disponible',
            isNote: true,
          ),
        ],
      ),
    );

    expect(find.text('Nota de contexto'), findsOneWidget);
    expect(find.textContaining('Registrada por'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
