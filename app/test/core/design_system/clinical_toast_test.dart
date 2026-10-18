import 'package:carer_record_app/core/design_system/clinical_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(
    Widget child, {
    bool disableAnimations = false,
    TextScaler? textScaler,
  }) => MaterialApp(
    builder: (context, routedChild) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: disableAnimations,
        textScaler: textScaler ?? MediaQuery.textScalerOf(context),
      ),
      child: ClinicalToastHost(child: routedChild!),
    ),
    home: Scaffold(body: child),
  );

  setUp(ClinicalToast.dismissAll);

  void toastTestWidgets(String name, WidgetTesterCallback body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        ClinicalToast.dismissAll();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 500));
      }
    });
  }

  toastTestWidgets('success and failure default to three seconds', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    ClinicalToast.success(context, message: 'Éxito');
    await tester.pump();
    expect(find.text('Éxito'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2, milliseconds: 999));
    expect(find.text('Éxito'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.text('Éxito'), findsNothing);

    ClinicalToast.failure(context, message: 'Fallo');
    await tester.pump();
    expect(find.text('Fallo'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2, milliseconds: 999));
    expect(find.text('Fallo'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.text('Fallo'), findsNothing);
  });

  toastTestWidgets('details give success and failure exactly four seconds', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    for (final show in <void Function()>[
      () => ClinicalToast.success(
        context,
        message: 'Éxito detalle',
        withDetails: true,
      ),
      () => ClinicalToast.failure(
        context,
        message: 'Fallo detalle',
        withDetails: true,
      ),
    ]) {
      show();
      await tester.pump();
      final message = find.textContaining('detalle');
      expect(message, findsOneWidget);
      await tester.pump(const Duration(seconds: 3, milliseconds: 999));
      expect(message, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(message, findsNothing);
    }
  });

  toastTestWidgets(
    'new emission immediately replaces, including same identifier',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      ClinicalToast.failure(context, message: 'Antes', identifier: 'same');
      await tester.pump();
      ClinicalToast.success(context, message: 'Después', identifier: 'same');
      await tester.pump();
      expect(find.text('Antes'), findsNothing);
      expect(find.text('Después'), findsOneWidget);
      final oldClose = tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Cerrar aviso'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed!;
      ClinicalToast.failure(context, message: 'Reemplazo');
      await tester.pump();
      oldClose();
      await tester.pump();
      expect(find.text('Después'), findsNothing);
      expect(find.text('Reemplazo'), findsOneWidget);
    },
  );

  toastTestWidgets('burst shows latest immediately with fresh lifetime', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    ClinicalToast.success(context, message: 'Uno');
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    ClinicalToast.failure(context, message: 'Dos');
    ClinicalToast.success(context, message: 'Último');
    await tester.pump();
    expect(find.text('Uno'), findsNothing);
    expect(find.text('Dos'), findsNothing);
    expect(find.text('Último'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2, milliseconds: 999));
    expect(find.text('Último'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.text('Último'), findsNothing);
  });

  toastTestWidgets('manual close and dismissAll clear visible toast', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    ClinicalToast.success(context, message: 'Cerrar');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cerrar aviso'));
    await tester.pump();
    expect(find.text('Cerrar'), findsNothing);
    ClinicalToast.failure(context, message: 'Limpiar');
    await tester.pump();
    ClinicalToast.dismissAll();
    await tester.pump();
    expect(find.text('Limpiar'), findsNothing);
  });

  toastTestWidgets('show then dismiss before first frame never appears', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    ClinicalToast.success(context, message: 'Dismissed before frame');
    ClinicalToast.dismissAll();
    await tester.pump();
    expect(find.text('Dismissed before frame'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  toastTestWidgets('toast overlays modal and honors reduced motion', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
        disableAnimations: true,
      ),
    );
    showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(title: Text('Modal')),
    );
    await tester.pumpAndSettle();
    ClinicalToast.success(context, message: 'Aviso modal');
    await tester.pump();
    expect(find.text('Modal'), findsOneWidget);
    expect(find.text('Aviso modal'), findsOneWidget);
    await tester.tap(find.byTooltip('Cerrar aviso'));
    await tester.pump();
    expect(find.text('Aviso modal'), findsNothing);
    expect(find.text('Modal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  toastTestWidgets(
    'host teardown cancels current toast and allows fresh host',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      ClinicalToast.success(context, message: 'Viejo');
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(
        app(
          Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      ClinicalToast.success(context, message: 'Nuevo');
      await tester.pumpAndSettle();
      expect(find.text('Viejo'), findsNothing);
      expect(find.text('Nuevo'), findsOneWidget);
    },
  );

  toastTestWidgets(
    'new toast remains visible after originating route is popped',
    (tester) async {
      late BuildContext homeContext;
      late BuildContext routeContext;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) {
              homeContext = context;
              return const SizedBox();
            },
          ),
        ),
      );
      Navigator.of(homeContext).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => Builder(
            builder: (origin) {
              routeContext = origin;
              return const Scaffold(body: Text('Origin route'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      ClinicalToast.failure(routeContext, message: 'Old route notice');
      await tester.pump();
      expect(find.text('Old route notice'), findsOneWidget);
      Navigator.of(routeContext).pop();
      await tester.pumpAndSettle();
      ClinicalToast.success(homeContext, message: 'Operation completed');
      await tester.pump();
      expect(find.text('Old route notice'), findsNothing);
      expect(find.text('Operation completed'), findsOneWidget);
    },
  );

  toastTestWidgets('wraps enlarged text within narrow width', (tester) async {
    late BuildContext context;
    tester.view.physicalSize = const Size(300, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
        textScaler: const TextScaler.linear(2),
      ),
    );
    ClinicalToast.success(
      context,
      message: 'Mensaje suficientemente largo para varias líneas',
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      MediaQuery.textScalerOf(tester.element(find.textContaining('Mensaje'))),
      const TextScaler.linear(2),
    );
    expect(
      tester.getRect(find.textContaining('Mensaje')).right,
      lessThanOrEqualTo(300),
    );
  });
}
