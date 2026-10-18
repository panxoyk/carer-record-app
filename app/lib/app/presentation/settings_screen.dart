import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/clinical_design_system.dart';
import '../../core/router/administration_navigation.dart';
import '../../domains/auth/presentation/auth_providers.dart';
import '../../domains/auth/presentation/sign_out_action.dart';
import '../../domains/institutional/domain/iam_entities.dart';
import '../../domains/institutional/presentation/iam_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contexts = ref.watch(iamContextsProvider);
    final iam = ref.watch(iamContextProvider);
    final session = ref.watch(sessionProvider);
    return Scaffold(
      bottomNavigationBar: const ClinicalBottomNavigation(selectedIndex: 1),
      appBar: clinicalAppBar(title: 'Ajustes'),
      body: iam.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            const Center(child: Text('No fue posible cargar el perfil.')),
        data: (profile) {
          if (profile == null) {
            return const Center(
              child: Text('No fue posible cargar el perfil.'),
            );
          }
          final organizations = (contexts.valueOrNull ?? const <IamContext>[])
              .where(
                (organization) =>
                    organization.profileStatus == 'active' &&
                    organization.membershipStatus == 'active',
              )
              .toList();
          final selected = ref.watch(selectedOrganizationProvider);
          final displayedContext =
              organizations
                  .where(
                    (organization) =>
                        organization.organizationId == selected?.organizationId,
                  )
                  .firstOrNull ??
              organizations
                  .where(
                    (organization) =>
                        organization.organizationId == profile.organizationId,
                  )
                  .firstOrNull;
          final administrationDestinations = administrationNavigationFor(
            profile,
          );
          final active =
              (displayedContext?.membershipStatus ??
                  profile.membershipStatus) ==
              'active';
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ClinicalCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: ClinicalColors.mint,
                      child: Text(_initials(profile.displayName)),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.displayName,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(session?.user.email ?? 'No disponible'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              ClinicalCard(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.business_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: organizations.length > 1
                          ? DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                isExpanded: true,
                                value: displayedContext?.organizationId,
                                items: [
                                  for (final org in organizations)
                                    DropdownMenuItem<String>(
                                      value: org.organizationId,
                                      child: Text(org.organizationName),
                                    ),
                                ],
                                onChanged: (id) {
                                  if (id != null) {
                                    ref
                                        .read(
                                          selectedOrganizationProvider.notifier,
                                        )
                                        .select(id);
                                  }
                                },
                              ),
                            )
                          : Text(
                              displayedContext?.organizationName ??
                                  profile.organizationName,
                            ),
                    ),
                    SizedBox.square(
                      dimension: kMinInteractiveDimension,
                      child: Center(
                        child: Tooltip(
                          message: active
                              ? 'Membresía activa'
                              : 'Membresía inactiva',
                          child: Semantics(
                            label: active
                                ? 'Membresía activa'
                                : 'Membresía inactiva',
                            child: Icon(
                              active
                                  ? Icons.check_circle_outline
                                  : Icons.cancel_outlined,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (administrationDestinations.isNotEmpty) ...[
                ClinicalSettingsSection(
                  title: 'Administración institucional',
                  children: [
                    for (var i = 0; i < administrationDestinations.length; i++)
                      ClinicalSettingsRow(
                        label: administrationDestinations[i].label,
                        icon: switch (administrationDestinations[i].location) {
                          '/users' => Icons.group_outlined,
                          '/roles' => Icons.admin_panel_settings_outlined,
                          _ => Icons.assignment_ind_outlined,
                        },
                        isLast: i == administrationDestinations.length - 1,
                        onTap: () =>
                            context.go(administrationDestinations[i].location),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
              ],
              ClinicalSettingsSection(
                title: 'Herramientas',
                children: [
                  ClinicalSettingsRow(
                    label: 'Dictado y redacción',
                    icon: Icons.auto_awesome_outlined,
                    isLast: true,
                    onTap: () => context.go('/models'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ClinicalSettingsRow(
                label: 'Cerrar sesión',
                icon: Icons.logout,
                destructive: true,
                onTap: () => signOutAction(context, ref),
                isLast: true,
              ),
            ],
          );
        },
      ),
    );
  }
}

String _initials(String name) => name
    .split(' ')
    .where((part) => part.isNotEmpty)
    .take(2)
    .map((part) => part[0])
    .join();
