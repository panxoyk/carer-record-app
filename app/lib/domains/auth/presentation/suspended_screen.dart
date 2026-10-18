import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/clinical_design_system.dart';
import 'sign_out_action.dart';

class SuspendedScreen extends ConsumerWidget {
  const SuspendedScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: clinicalAppBar(title: 'Cuenta suspendida'),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Tu cuenta está suspendida. Contacta a administración.'),
          TextButton(
            onPressed: () => signOutAction(context, ref),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    ),
  );
}
