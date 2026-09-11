import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domains/auth/presentation/auth_providers.dart';
import '../../domains/auth/presentation/auth_screens.dart';
import '../../domains/patient/presentation/patient_screens.dart';
import '../../domains/users/presentation/users_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final gate = ref.watch(authGateProvider);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: gate,
    redirect: (context, state) async {
      final location = state.matchedLocation;
      const publicPaths = {'/login', '/recover'};
      if (gate.session == null) {
        return publicPaths.contains(location) ? null : '/login';
      }
      if (gate.recoveringPassword) {
        return location == '/update-password' ? null : '/update-password';
      }
      if (location == '/update-password') {
        return '/';
      }
      final practitioner = await ref.read(currentPractitionerProvider.future);
      if (practitioner == null || !practitioner.isActive) {
        return location == '/suspended' ? null : '/suspended';
      }
      if (publicPaths.contains(location) || location == '/suspended') {
        return '/';
      }
      if (location == '/' && !practitioner.isAdministrator) {
        return '/patients';
      }
      if (location == '/users' && !practitioner.isAdministrator) {
        return '/';
      }
      if (state.uri.path.startsWith('/patients') &&
          practitioner.isAdministrator) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const ProtectedShell()),
      GoRoute(path: '/login', builder: (_, __) => const SignInScreen()),
      GoRoute(
        path: '/recover',
        builder: (_, __) => const RecoverPasswordScreen(),
      ),
      GoRoute(
        path: '/update-password',
        builder: (_, __) => const UpdatePasswordScreen(),
      ),
      GoRoute(path: '/suspended', builder: (_, __) => const SuspendedScreen()),
      GoRoute(path: '/users', builder: (_, __) => const UsersScreen()),
      GoRoute(path: '/patients', builder: (_, __) => const PatientsScreen()),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(
        path: '/patients/:id',
        builder:
            (_, state) =>
                PatientDetailScreen(patientId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/patients/:id/details',
        builder:
            (_, state) => PatientInformationScreen(
              patientId: state.pathParameters['id']!,
            ),
      ),
    ],
  );
});

class ProtectedShell extends ConsumerWidget {
  const ProtectedShell({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final practitioner = ref.watch(currentPractitionerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Carer Record')),
      body: Center(
        child: practitioner.when(
          loading: () => const CircularProgressIndicator(),
          error: (_, __) => const Text('No fue posible cargar tu perfil.'),
          data:
              (p) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Sesión activa: ${p?.displayName ?? ''}'),
                  const SizedBox(height: 8),
                  const Text('Consulta pacientes autorizados desde tu cuenta.'),
                  if (p != null && !p.isAdministrator)
                    TextButton(
                      onPressed: () => context.go('/patients'),
                      child: const Text('Ver pacientes'),
                    ),
                  if (p?.isAdministrator ?? false)
                    TextButton(
                      onPressed: () => context.go('/users'),
                      child: const Text('Gestionar usuarios'),
                    ),
                  TextButton(
                    onPressed: () => ref.read(authRepositoryProvider).signOut(),
                    child: const Text('Cerrar sesión'),
                  ),
                ],
              ),
        ),
      ),
    );
  }
}

class SuspendedScreen extends ConsumerWidget {
  const SuspendedScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Tu cuenta está suspendida. Contacta a administración.'),
          TextButton(
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    ),
  );
}
