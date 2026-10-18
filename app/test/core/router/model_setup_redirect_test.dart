import 'package:carer_record_app/core/router/app_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('modelSetupRedirect', () {
    test('keeps an authenticated user on setup while models are missing', () {
      expect(
        modelSetupRedirect(
          location: '/setup',
          modelsReady: false,
          skipped: false,
          hasSession: true,
        ),
        isNull,
      );
    });

    test('redirects login to setup when models are missing', () {
      expect(
        modelSetupRedirect(
          location: '/login',
          modelsReady: false,
          skipped: false,
          hasSession: false,
        ),
        '/setup',
      );
    });

    test(
      'skip lets login and authorized destinations pass without repeating',
      () {
        for (final location in ['/login', '/patients']) {
          expect(
            modelSetupRedirect(
              location: location,
              modelsReady: false,
              skipped: true,
              hasSession: location != '/login',
            ),
            isNull,
          );
        }
      },
    );

    test('ready setup sends signed-out users to login and leaves signed-in routing on setup', () {
      expect(
        modelSetupRedirect(
          location: '/setup',
          modelsReady: true,
          skipped: false,
          hasSession: false,
        ),
        '/login',
      );
      expect(
        modelSetupRedirect(
          location: '/setup',
          modelsReady: true,
          skipped: false,
          hasSession: true,
        ),
        isNull,
      );
    });

    test(
      'keeps completed first-run setup until Continue for either auth state',
      () {
        for (final hasSession in [false, true]) {
          expect(
            modelSetupRedirect(
              location: '/setup',
              modelsReady: true,
              skipped: false,
              setupAwaitingContinue: true,
              hasSession: hasSession,
            ),
            isNull,
          );
        }
      },
    );

    test('ready models at startup leave setup automatically', () {
      expect(
        modelSetupRedirect(
          location: '/setup',
          modelsReady: true,
          skipped: false,
          hasSession: false,
        ),
        '/login',
      );
      expect(
        modelSetupRedirect(
          location: '/setup',
          modelsReady: true,
          skipped: false,
          hasSession: true,
        ),
        isNull,
      );
    });

    test('recovery routes bypass model setup', () {
      for (final location in ['/recover', '/update-password']) {
        expect(
          modelSetupRedirect(
            location: location,
            modelsReady: false,
            skipped: false,
            hasSession: false,
          ),
          isNull,
        );
      }
    });

    test('authenticated password recovery redirects to update password before setup', () {
      expect(
        modelSetupRedirect(
          location: '/setup',
          modelsReady: false,
          skipped: false,
          hasSession: true,
          recoveringPassword: true,
        ),
        '/update-password',
      );
    });

    test('models management is not public without a session', () {
      expect(
        modelSetupRedirect(
          location: '/models',
          modelsReady: true,
          skipped: false,
          hasSession: false,
        ),
        '/login',
      );
    });

    test(
      'authenticated model management stays available when models are missing',
      () {
        expect(
          modelSetupRedirect(
            location: '/models',
            modelsReady: false,
            skipped: false,
            hasSession: true,
          ),
          isNull,
        );
      },
    );

    test('a management skip lets authenticated navigation proceed while models are missing', () {
      expect(
        modelSetupRedirect(
          location: '/settings',
          modelsReady: false,
          skipped: true,
          hasSession: true,
        ),
        isNull,
      );
    });
  });
}
