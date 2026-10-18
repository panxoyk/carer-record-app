import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/clinical_design_system.dart';
import '../../domains/auth/presentation/sign_out_action.dart';
import '../../domains/institutional/presentation/iam_providers.dart';

class ProtectedShell extends ConsumerWidget {
  const ProtectedShell({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iam = ref.watch(iamContextProvider);
    return Scaffold(
      appBar: clinicalAppBar(title: 'Carer Record'),
      body: Center(
        child: iam.when(
          loading: () => const CircularProgressIndicator(),
          error: (_, __) => const Text('No fue posible cargar tu perfil.'),
          data: (p) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Sesión activa: ${p?.displayName ?? ''}'),
              if ((ref.read(iamContextsProvider).valueOrNull?.length ?? 0) > 1)
                TextButton(
                  onPressed: () => context.go('/select-organization'),
                  child: Text(
                    'Organización: ${p?.organizationName ?? ''} · Cambiar',
                  ),
                ),
              const SizedBox(height: 8),
              const Text('Consulta pacientes autorizados desde tu cuenta.'),
              if (p?.allows('clinical.census.read') == true &&
                  p?.allows('clinical.patient.read') == true)
                TextButton(
                  onPressed: () => context.go('/patients'),
                  child: const Text('Ver pacientes'),
                ),
              if (p?.allows('iam.membership.read') ?? false)
                TextButton(
                  onPressed: () => context.go('/users'),
                  child: const Text('Gestionar usuarios'),
                ),
              if (p?.allows('iam.role.read') == true &&
                  p?.allows('iam.role.manage') == true)
                TextButton(
                  onPressed: () => context.go('/roles'),
                  child: const Text('Roles y permisos'),
                ),
              if (p?.allows('clinical.assignment.manage') ?? false)
                TextButton(
                  onPressed: () => context.go('/assignments'),
                  child: const Text('Gestionar asignaciones'),
                ),
              TextButton(
                onPressed: () => signOutAction(context, ref),
                child: const Text('Cerrar sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
