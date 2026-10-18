import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/clinical_design_system.dart';
import '../../../core/session/authorization_refresh.dart';
import 'iam_providers.dart';

class OrganizationSelectionScreen extends ConsumerWidget {
  const OrganizationSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contexts = ref.watch(iamContextsProvider);
    return Scaffold(
      appBar: clinicalAppBar(title: 'Seleccionar organización'),
      body: contexts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: Text('No fue posible cargar tus organizaciones.'),
        ),
        data: (items) => ListView(
          children: [
            for (final item in items)
              ListTile(
                title: Text(item.organizationName),
                onTap: () {
                  ref
                      .read(selectedOrganizationProvider.notifier)
                      .select(item.organizationId);
                  ref.read(authorizationRefreshProvider)();
                  context.go('/');
                },
              ),
          ],
        ),
      ),
    );
  }
}
