import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/administration_navigation.dart';
import '../../institutional/data/iam_models.dart';
import '../../institutional/data/iam_repository.dart';
import '../../institutional/presentation/iam_providers.dart';

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iam = ref.watch(iamContextProvider);
    final members = ref.watch(iamMembersProvider);
    final roles = ref.watch(iamRolesProvider);
    final assignments = ref.watch(iamRoleAssignmentsProvider);
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Administración institucional'),
          automaticallyImplyLeading: false,
          actions: [
            if (iam is AsyncData<IamContext?> &&
                iam.value?.allows('iam.membership.read') == true)
              PopupMenuButton<String>(
                tooltip: 'Navegación',
                icon: const Icon(Icons.menu),
                onSelected: (location) => context.go(location),
                itemBuilder:
                    (_) => [
                      for (final destination in administrationNavigationFor(
                        iam.value!,
                      ))
                        PopupMenuItem(
                          value: destination.location,
                          child: Text(destination.label),
                        ),
                    ],
              ),
          ],
        ),
        floatingActionButton:
            iam is AsyncData<IamContext?> &&
                    iam.value?.allows('iam.membership.manage') == true &&
                    iam.value?.allows('iam.role.assign') == true
                ? FloatingActionButton.extended(
                  onPressed: () => _createMember(context, ref),
                  icon: const Icon(Icons.person_add),
                  label: const Text('Agregar miembro'),
                )
                : null,
        body: iam.when(
          skipLoadingOnRefresh: false,
          skipError: false,
          loading: () => const Center(child: CircularProgressIndicator()),
          error:
              (_, __) => _retry(
                () => invalidateAuthorizationAndData(ref),
                'No fue posible validar permisos.',
              ),
          data: (ctx) {
            if (ctx == null || !ctx.allows('iam.membership.read')) {
              return const Center(
                child: Text('No tienes permiso para administrar miembros.'),
              );
            }
            return Column(
              children: [
                Expanded(
                  child: members.when(
                    skipLoadingOnRefresh: false,
                    skipError: false,
                    loading:
                        () => const Center(child: CircularProgressIndicator()),
                    error:
                        (_, __) => _retry(
                          () => ref.invalidate(iamMembersProvider),
                          'No fue posible cargar los miembros.',
                        ),
                    data:
                        (items) => roles.when(
                          skipLoadingOnRefresh: false,
                          skipError: false,
                          loading:
                              () => const Center(
                                child: CircularProgressIndicator(),
                              ),
                          error:
                              (_, __) => _retry(
                                () => ref.invalidate(iamRolesProvider),
                                'No fue posible cargar los roles.',
                              ),
                          data:
                              (availableRoles) => assignments.when(
                                skipLoadingOnRefresh: false,
                                skipError: false,
                                loading:
                                    () => const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                error:
                                    (_, __) => _retry(
                                      () => ref.invalidate(
                                        iamRoleAssignmentsProvider,
                                      ),
                                      'No fue posible cargar las asignaciones de rol.',
                                    ),
                                data: (byMember) {
                                  final visible =
                                      items
                                          .where(
                                            (m) =>
                                                m.membershipId !=
                                                    ctx.membershipId &&
                                                isVisibleInMemberDirectory(m),
                                          )
                                          .toList();
                                  return ListView(
                                    padding: const EdgeInsets.only(bottom: 88),
                                    children: [
                                      for (final member in visible)
                                        _MemberTile(
                                          member: member,
                                          roles: availableRoles,
                                          assignments:
                                              byMember[member.membershipId] ??
                                              [],
                                          context: ctx,
                                        ),
                                      if (visible.isEmpty)
                                        const ListTile(
                                          title: Text(
                                            'No hay miembros disponibles.',
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                        ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({
    required this.member,
    required this.roles,
    required this.assignments,
    required this.context,
  });
  final IamMember member;
  final List<IamRole> roles;
  final List<IamRoleAssignment> assignments;
  final IamContext context;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = this.context.allows('iam.membership.manage');
    final canAssign = this.context.allows('iam.role.assign');
    final grantableRoles = eligibleRolesForGrant(
      roles: roles,
      assignments: assignments,
      membershipId: member.membershipId,
      now: DateTime.now().toUtc(),
    );
    final active = member.membershipStatus == 'active';
    final targetEligible = isEligibleForNewAssignment(
      member,
      now: DateTime.now().toUtc(),
    );
    final roleRows = assignments.where((a) => !a.protected).toList();
    return ExpansionTile(
      key: ValueKey(member.membershipId),
      title: Text(member.displayName),
      subtitle:
          member.membershipStatus == 'suspended'
              ? const Text('Membresía suspendida')
              : null,
      children: [
        for (final assignment in roleRows)
          ListTile(
            dense: true,
            title: Text(assignment.roleName),
            subtitle: Text(
              assignment.revokedAt == null
                  ? 'Vigente desde ${assignment.validFrom}'
                  : 'Revocado · vigente desde ${assignment.validFrom}',
            ),
            trailing:
                canAssign && assignment.revokedAt == null
                    ? IconButton(
                      tooltip: 'Revocar rol',
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed:
                          () => _mutate(
                            context,
                            ref,
                            (attempt) => ref
                                .read(iamRepositoryProvider)
                                .revokeRole(
                                  organizationId: this.context.organizationId,
                                  assignmentId: assignment.assignmentId,
                                  attempt: attempt,
                                ),
                          ),
                    )
                    : null,
          ),
        if (canManage)
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed:
                    () => _mutate(
                      context,
                      ref,
                      (attempt) => ref
                          .read(iamRepositoryProvider)
                          .updateMembership(
                            organizationId: this.context.organizationId,
                            membershipId: member.membershipId,
                            status: active ? 'suspended' : 'active',
                            attempt: attempt,
                          ),
                    ),
                child: Text(
                  active ? 'Suspender membresía' : 'Activar membresía',
                ),
              ),
            ],
          ),
        if (canAssign && targetEligible && grantableRoles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: DropdownButtonFormField<String>(
              key: ValueKey('role-${member.membershipId}'),
              decoration: const InputDecoration(
                labelText: 'Asignar rol ordinario',
              ),
              items: [
                for (final role in grantableRoles)
                  DropdownMenuItem(value: role.id, child: Text(role.name)),
              ],
              onChanged: (roleId) {
                if (roleId != null) {
                  _mutate(
                    context,
                    ref,
                    (attempt) => ref
                        .read(iamRepositoryProvider)
                        .grantRole(
                          organizationId: this.context.organizationId,
                          membershipId: member.membershipId,
                          roleId: roleId,
                          attempt: attempt,
                        ),
                    usesValidFrom: true,
                  );
                }
              },
            ),
          ),
      ],
    );
  }
}

Widget _retry(VoidCallback retry, String message) => Center(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(message),
      TextButton(onPressed: retry, child: const Text('Reintentar')),
    ],
  ),
);

Future<void> _mutate(
  BuildContext context,
  WidgetRef ref,
  Future<AdminOperationResult> Function(AdminOperationAttempt) action, {
  AdminOperationAttempt? attempt,
  bool usesValidFrom = false,
}) async {
  attempt ??= newAdminOperationAttempt(usesValidFrom: usesValidFrom);
  try {
    final result = await action(attempt);
    if (!context.mounted) return;
    if (result.success) {
      invalidateAuthorizationAndData(ref);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cambio aplicado.')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No fue posible aplicar el cambio.')),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No fue posible aplicar el cambio. Puedes reintentar.'),
          action: SnackBarAction(
            label: 'Reintentar',
            onPressed:
                () => _mutate(
                  context,
                  ref,
                  action,
                  attempt: attempt,
                  usesValidFrom: usesValidFrom,
                ),
          ),
        ),
      );
    }
  }
}

Future<void> _createMember(BuildContext context, WidgetRef ref) async {
  final iam = ref.read(iamContextProvider).valueOrNull;
  final roles = ref.read(iamRolesProvider).valueOrNull ?? const <IamRole>[];
  if (iam == null ||
      !iam.allows('iam.membership.manage') ||
      !iam.allows('iam.role.assign') ||
      roles.isEmpty) {
    return;
  }
  var email = '';
  var password = '';
  var name = '';
  String? roleId = roles.first.id;
  final idempotencyKey = newIdempotencyKey();
  String? error;
  var saving = false;
  await showDialog<void>(
    context: context,
    builder:
        (dialogContext) => StatefulBuilder(
          builder:
              (dialogContext, setState) => AlertDialog(
                title: const Text('Agregar miembro'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        onChanged: (value) => name = value,
                        decoration: const InputDecoration(
                          labelText: 'Nombre visible',
                        ),
                      ),
                      TextField(
                        onChanged: (value) => email = value,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Correo'),
                      ),
                      TextField(
                        onChanged: (value) => password = value,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText:
                              'Contraseña inicial (mínimo 12 caracteres)',
                        ),
                      ),
                      DropdownButtonFormField<String>(
                        value: roleId,
                        items: [
                          for (final role in roles)
                            DropdownMenuItem(
                              value: role.id,
                              child: Text(role.name),
                            ),
                        ],
                        onChanged: (value) => setState(() => roleId = value),
                      ),
                      if (error != null)
                        Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed:
                        saving ? null : () => Navigator.pop(dialogContext),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed:
                        saving
                            ? null
                            : () async {
                              if (name.trim().isEmpty ||
                                  !email.contains('@') ||
                                  password.length < 12 ||
                                  roleId == null) {
                                setState(
                                  () => error = 'Revisa los datos ingresados.',
                                );
                                return;
                              }
                              setState(() {
                                saving = true;
                                error = null;
                              });
                              try {
                                await ref
                                    .read(iamRepositoryProvider)
                                    .createMember(
                                      organizationId: iam.organizationId,
                                      email: email,
                                      password: password,
                                      displayName: name,
                                      roleId: roleId!,
                                      idempotencyKey: idempotencyKey,
                                    );
                                invalidateAuthorizationAndData(ref);
                                if (dialogContext.mounted) {
                                  Navigator.pop(dialogContext);
                                }
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Miembro agregado.'),
                                    ),
                                  );
                                }
                              } catch (_) {
                                if (dialogContext.mounted) {
                                  setState(() {
                                    saving = false;
                                    error =
                                        'No fue posible agregar el miembro. Puedes reintentar.';
                                  });
                                }
                              }
                            },
                    child: const Text('Crear'),
                  ),
                ],
              ),
        ),
  );
}
