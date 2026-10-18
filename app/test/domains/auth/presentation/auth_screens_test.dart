import 'dart:async';

import 'package:carer_record_app/core/design_system/clinical_design_system.dart';
import 'package:carer_record_app/domains/auth/data/auth_repository.dart';
import 'package:carer_record_app/domains/auth/presentation/auth_providers.dart';
import 'package:carer_record_app/domains/auth/presentation/auth_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('SignInScreen', () {
    testWidgets('shows institutional brand, card, and copy', (tester) async {
      await _pumpAuth(tester, const SignInScreen());

      expect(find.text('Carer Record'), findsOneWidget);
      expect(find.text('Contexto para el cuidado clínico'), findsOneWidget);
      expect(find.text('Iniciar sesión'), findsNWidgets(2));
      expect(find.text('Ingresa con tu cuenta institucional.'), findsOneWidget);
      expect(
        find.text('Contacta al administrador de tu institución.'),
        findsOneWidget,
      );
      expect(find.byType(ClinicalCard), findsOneWidget);
    });

    testWidgets(
      'fields use theme decoration and submit button fills card width',
      (tester) async {
        await _pumpAuth(tester, const SignInScreen());

        for (final fieldFinder in [
          find.byType(TextField).first,
          find.byType(TextField).last,
        ]) {
          final field = tester.widget<TextField>(fieldFinder);
          expect(field.decoration, isNotNull);
          final inputTheme = Theme.of(tester.element(fieldFinder))
              .inputDecorationTheme;
          expect(inputTheme.filled, isTrue);
          expect(inputTheme.fillColor, Colors.white);
        }
        final buttonRect = tester.getRect(find.byType(FilledButton).first);
        final cardRect = tester.getRect(find.byType(ClinicalCard));
        expect(buttonRect.left, cardRect.left + ClinicalSpacing.section);
        expect(buttonRect.right, cardRect.right - ClinicalSpacing.section);
        final buttonTheme = Theme.of(
          tester.element(find.byType(FilledButton).first),
        ).filledButtonTheme.style!;
        expect(
          buttonTheme.backgroundColor!.resolve({}),
          ClinicalColors.mintDark,
        );
      },
    );

    testWidgets('password visibility toggle preserves entered value', (
      tester,
    ) async {
      await _pumpAuth(tester, const SignInScreen());
      await tester.enterText(find.byType(TextField).last, 'synthetic-pass');

      await tester.tap(find.byTooltip('Mostrar contraseña'));
      await tester.pump();

      expect(
        tester.widget<TextField>(find.byType(TextField).last).obscureText,
        isFalse,
      );
      expect(find.text('synthetic-pass'), findsOneWidget);
      expect(find.byTooltip('Ocultar contraseña'), findsOneWidget);
    });

    testWidgets(
      'email and password semantics are editable and toggle is labeled',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await _pumpAuth(tester, const SignInScreen());

        expect(find.bySemanticsLabel('Correo electrónico'), findsOneWidget);
        expect(find.bySemanticsLabel('Contraseña'), findsOneWidget);
        expect(
          tester.getSemantics(find.bySemanticsLabel('Correo electrónico')),
          matchesSemantics(
            label: 'Correo electrónico',
            isTextField: true,
            hasTapAction: true,
            hasFocusAction: true,
            isFocusable: true,
            hasEnabledState: true,
            isEnabled: true,
          ),
        );
        expect(
          tester.getSemantics(find.bySemanticsLabel('Contraseña')),
          matchesSemantics(
            label: 'Contraseña',
            isTextField: true,
            isObscured: true,
            hasTapAction: true,
            hasFocusAction: true,
            isFocusable: true,
            hasEnabledState: true,
            isEnabled: true,
          ),
        );
        expect(find.byTooltip('Mostrar contraseña'), findsOneWidget);
        final toggleSemantics = tester.getSemantics(
          find.byTooltip('Mostrar contraseña'),
        );
        expect(
          toggleSemantics,
          matchesSemantics(
            tooltip: 'Mostrar contraseña',
            isButton: true,
            hasTapAction: true,
            hasFocusAction: true,
            isFocusable: true,
            hasEnabledState: true,
            isEnabled: true,
          ),
        );
        semantics.dispose();
      },
    );

    testWidgets('loading disables submit and concurrent taps call once', (
      tester,
    ) async {
      final repository = _FakeAuthRepository()
        ..signInCompleter = Completer<void>();
      await _pumpAuth(tester, const SignInScreen(), repository: repository);
      await tester.tap(find.byType(FilledButton).first);
      await tester.pump();

      final busyButton = tester.widget<FilledButton>(
        find.byType(FilledButton).first,
      );
      expect(busyButton.onPressed, isNull);
      expect(find.text('Accediendo…'), findsOneWidget);
      expect(repository.signInCalls, 1);

      await tester.tap(find.byType(FilledButton).first);
      await tester.pump();
      expect(repository.signInCalls, 1);

      repository.signInCompleter!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('safe error preserves input and allows retry', (tester) async {
      final repository = _FakeAuthRepository()..failSignIn = true;
      await _pumpAuth(tester, const SignInScreen(), repository: repository);
      await tester.enterText(find.byType(TextField).first, 'care@example.test');
      await tester.enterText(find.byType(TextField).last, 'synthetic-password');
      await tester.tap(find.byType(FilledButton).first);
      await tester.pumpAndSettle();

      expect(
        find.text('No fue posible acceder. Revisa tus credenciales.'),
        findsOneWidget,
      );
      expect(find.text('care@example.test'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        'synthetic-password',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).last).obscureText,
        isTrue,
      );

      repository.failSignIn = false;
      await tester.tap(find.byType(FilledButton).first);
      await tester.pumpAndSettle();
      expect(repository.signInCalls, 2);
    });

    testWidgets('recovery link navigates using a minimal test router', (
      tester,
    ) async {
      final router = _authRouter(const SignInScreen());
      await _pumpRouter(tester, router);

      await tester.tap(find.text('¿Olvidaste tu contraseña?'));
      await tester.pumpAndSettle();

      expect(find.text('Recuperar contraseña'), findsOneWidget);
      router.dispose();
    });

    testWidgets(
      'fits narrow screen with keyboard, large text, and scroll access',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
            ],
            child: MaterialApp(
              theme: ClinicalTheme.build(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: const SignInScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(SingleChildScrollView), findsOneWidget);

        await tester.ensureVisible(find.byType(FilledButton).first);
        await tester.pumpAndSettle();
        final viewport = MediaQuery.of(tester.element(find.byType(Scaffold)));
        final visibleHeight = viewport.size.height - viewport.viewInsets.bottom;
        expect(find.byType(FilledButton).first.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(find.byType(FilledButton).first).bottom,
          lessThanOrEqualTo(visibleHeight),
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets('recovery and password-update screens render shared scaffold', (
    tester,
  ) async {
    await _pumpAuth(tester, const RecoverPasswordScreen());
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('Recuperar contraseña'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);

    await _pumpAuth(tester, const UpdatePasswordScreen());
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('Definir nueva contraseña'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpAuth(
  WidgetTester tester,
  Widget screen, {
  _FakeAuthRepository? repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          repository ?? _FakeAuthRepository(),
        ),
      ],
      child: MaterialApp(theme: ClinicalTheme.build(), home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

GoRouter _authRouter(Widget login) => GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(path: '/login', builder: (_, __) => login),
    GoRoute(
      path: '/recover',
      builder: (_, __) => const RecoverPasswordScreen(),
    ),
  ],
);

Future<void> _pumpRouter(WidgetTester tester, GoRouter router) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
      ],
      child: MaterialApp.router(
        theme: ClinicalTheme.build(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeAuthRepository implements AuthRepository {
  int signInCalls = 0;
  bool failSignIn = false;
  Completer<void>? signInCompleter;

  @override
  Session? get session => null;

  @override
  Stream<AuthState> get changes => const Stream<AuthState>.empty();

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCalls++;
    await signInCompleter?.future;
    if (failSignIn) throw Exception('synthetic secret detail');
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> sendPasswordRecovery(String email) async {}

  @override
  Future<void> updatePassword(String password) async {}
}
