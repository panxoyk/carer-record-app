import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/clinical/clinical_vocabulary.dart';
import '../../core/design_system/clinical_design_system.dart';
import '../../core/design_system/clinical_toast.dart';
import '../../core/security/biometric_lock.dart';
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
      extendBody: true,
      bottomNavigationBar: const ClinicalBottomNavigation(
        current: ClinicalTab.settings,
      ),
      body: SafeArea(
        bottom: false,
        child: iam.when(
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
                          organization.organizationId ==
                          selected?.organizationId,
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
            final profession = Profession.fromWire(profile.profession);
            final biometric = ref.watch(biometricLockProvider);
            final signedInAt = DateTime.tryParse(
              session?.user.lastSignInAt ?? '',
            );
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ClinicalLargeTitle(
                    'Ajustes',
                    padding: EdgeInsets.fromLTRB(4, 16, 4, 16),
                  ),
                  ClinicalCard(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        ClinicalAvatar(
                          initials: clinicalInitials(profile.displayName),
                          size: 56,
                          background: ClinicalColors.softMint,
                          foreground: ClinicalColors.mintDark,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.displayName,
                                style: ClinicalTextStyles.headline,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                session?.user.email ?? 'No disponible',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: ClinicalColors.secondary,
                                ),
                              ),
                              if (profession != null)
                                Text(
                                  profession.roleLabel,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: ClinicalColors.secondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        ClinicalBadge(
                          label: active ? 'Activo' : 'Inactivo',
                          color: active
                              ? ClinicalColors.softMint
                              : ClinicalColors.fillSubtle,
                          textColor: active
                              ? ClinicalColors.mintText
                              : ClinicalColors.secondary,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  ClinicalCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: ClinicalColors.softMint,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.business_outlined,
                            size: 17,
                            color: ClinicalColors.mintDark,
                          ),
                        ),
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
                                              selectedOrganizationProvider
                                                  .notifier,
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
                          child: Semantics(
                            container: true,
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
                                        ? Icons.check_circle_rounded
                                        : Icons.cancel_outlined,
                                    color: active
                                        ? ClinicalColors.mintDark
                                        : ClinicalColors.destructive,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  ClinicalSettingsSection(
                    title: 'Perfil institucional',
                    children: [
                      ClinicalSettingsRow(
                        label: 'Nombre',
                        value: profile.displayName,
                        icon: Icons.person_outline_rounded,
                      ),
                      ClinicalSettingsRow(
                        label: 'Rol',
                        value:
                            profession?.roleLabel ?? 'Sin profesión registrada',
                        icon: Icons.medical_services_outlined,
                        isLast: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ClinicalSettingsSection(
                    title: 'Sistema',
                    children: [
                      ClinicalSettingsRow(
                        label: 'Identificación institucional',
                        value: profile.localIdentifier ?? 'No registrada',
                        icon: Icons.badge_outlined,
                      ),
                      const ClinicalSettingsRow(
                        label: 'Estado de conexión',
                        value: 'Conectado',
                        icon: Icons.wifi_rounded,
                        isLast: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const ClinicalSettingsSection(
                    title: 'Integración',
                    children: [
                      ClinicalSettingsRow(
                        label: 'Integración con ficha clínica',
                        value: 'HAPI FHIR',
                        icon: Icons.link_rounded,
                        isLast: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (administrationDestinations.isNotEmpty) ...[
                    ClinicalSettingsSection(
                      title: 'Administración institucional',
                      children: [
                        for (
                          var i = 0;
                          i < administrationDestinations.length;
                          i++
                        )
                          ClinicalSettingsRow(
                            label: administrationDestinations[i].label,
                            icon: switch (administrationDestinations[i]
                                .location) {
                              '/users' => Icons.group_outlined,
                              '/roles' => Icons.admin_panel_settings_outlined,
                              _ => Icons.assignment_ind_outlined,
                            },
                            isLast: i == administrationDestinations.length - 1,
                            onTap: () => context.go(
                              administrationDestinations[i].location,
                            ),
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
                  ClinicalSettingsSection(
                    title: 'Seguridad',
                    children: [
                      ClinicalSettingsRow(
                        label: 'Sesión activa',
                        value: signedInAt == null
                            ? 'Activa'
                            : _sessionDuration(
                                DateTime.now().difference(signedInAt),
                              ),
                        icon: Icons.schedule_rounded,
                      ),
                      _BiometricRow(
                        enabled: biometric.enabled,
                        onChanged: (value) async {
                          final ok = await ref
                              .read(biometricLockProvider)
                              .setEnabled(value);
                          if (!ok && value && context.mounted) {
                            ClinicalToast.failure(
                              context,
                              message: 'La biometría no está disponible en este dispositivo.',
                            );
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ClinicalCard(
                    radius: ClinicalRadii.large,
                    elevated: false,
                    child: ClinicalSettingsRow(
                      label: 'Cerrar sesión',
                      icon: Icons.logout,
                      destructive: true,
                      onTap: () => signOutAction(context, ref),
                      isLast: true,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Carer-Record',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: ClinicalColors.tertiary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Uso exclusivo personal clínico autorizado',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: ClinicalColors.tertiary,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

String _sessionDuration(Duration duration) {
  if (duration.isNegative) return 'Activa';
  final hours = duration.inHours, minutes = duration.inMinutes % 60;
  return hours == 0 ? '$minutes min' : '$hours h $minutes min';
}

class _BiometricRow extends StatelessWidget {
  const _BiometricRow({required this.enabled, required this.onChanged});
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: ClinicalColors.softMint,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.fingerprint_rounded,
              size: 17,
              color: ClinicalColors.mintDark,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Biometría / Face ID', style: TextStyle(fontSize: 16)),
          ),
          Switch(value: enabled, onChanged: onChanged),
        ],
      ),
    ),
  );
}
