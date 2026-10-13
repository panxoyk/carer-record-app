import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/clinical_design_system.dart';
import '../../../core/design_system/anchored_selector.dart';
import '../../../core/time/clinical_time.dart';
import 'package:go_router/go_router.dart';

import '../../institutional/data/iam_models.dart';
import '../../institutional/data/iam_repository.dart';
import '../../institutional/presentation/iam_providers.dart';

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  /// El texto vive en el State y no en el campo: una recarga de permisos
  /// remonta la lista, y el campo debe conservar lo escrito y el foco.
  final _searchController = TextEditingController();
  var _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iam = ref.watch(iamContextProvider);
    final members = ref.watch(iamMembersProvider);
    final roles = ref.watch(iamRolesProvider);
    final assignments = ref.watch(iamRoleAssignmentsProvider);
    final canCreateUser =
        iam is AsyncData<IamContext?> &&
        iam.value?.allows('iam.membership.manage') == true &&
        iam.value?.allows('iam.role.assign') == true;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/settings');
      },
      child: Scaffold(
        appBar: clinicalBackAppBar(
          context,
          title: 'Gestión de usuarios',
          fallbackLocation: '/settings',
          tooltip: 'Volver a Ajustes',
          actions: [
            if (canCreateUser)
              IconButton(
                tooltip: 'Agregar usuario',
                icon: const Icon(Icons.person_add_alt),
                onPressed: () => _createMember(context, ref),
              ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(
            ClinicalSpacing.page,
            ClinicalSpacing.page,
            ClinicalSpacing.page,
            ClinicalSpacing.page,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: ClinicalSpacing.card),
                child: TextField(
                  controller: _searchController,
                  decoration: clinicalInputDecoration(
                    labelText: 'Nombre',
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: iam.when(
                  skipLoadingOnRefresh: false,
                  skipError: false,
                  loading:
                      () => const Center(child: CircularProgressIndicator()),
                  error:
                      (_, __) => _retry(
                        () => invalidateAuthorizationAndData(ref),
                        'No fue posible validar permisos.',
                      ),
                  data: (ctx) {
                    if (ctx == null || !ctx.allows('iam.membership.read')) {
                      return const Center(
                        child: Text(
                          'No tienes permiso para administrar miembros.',
                        ),
                      );
                    }
                    return members.when(
                      skipLoadingOnRefresh: false,
                      skipError: false,
                      loading:
                          () =>
                              const Center(child: CircularProgressIndicator()),
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
                                    final query = _query.trim().toLowerCase();
                                    final visible =
                                        items
                                            .where(
                                              (m) =>
                                                  m.membershipId !=
                                                      ctx.membershipId &&
                                                  isVisibleInMemberDirectory(
                                                    m,
                                                  ) &&
                                                  (query.isEmpty ||
                                                      m.displayName
                                                          .toLowerCase()
                                                          .contains(query)),
                                            )
                                            .toList();
                                    return ListView(
                                      padding: EdgeInsets.zero,
                                      children: [
                                        for (final member in visible)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: ClinicalSpacing.item,
                                            ),
                                            child: _MemberTile(
                                              member: member,
                                              roles: availableRoles,
                                              assignments:
                                                  byMember[member
                                                      .membershipId] ??
                                                  [],
                                              context: ctx,
                                            ),
                                          ),
                                        if (visible.isEmpty)
                                          ListTile(
                                            title: Text(
                                              _query.trim().isEmpty
                                                  ? 'No hay miembros disponibles.'
                                                  : 'Ningún miembro coincide con la búsqueda.',
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                          ),
                    );
                  },
                ),
              ),
            ],
          ),
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
    final showRolePicker =
        canAssign && targetEligible && grantableRoles.isNotEmpty;
    return ClinicalCard(
      radius: ClinicalRadii.card,
      padding: const EdgeInsets.all(ClinicalSpacing.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            member.displayName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (member.membershipStatus == 'suspended') ...[
            const SizedBox(height: ClinicalSpacing.compact),
            const Text('Membresía suspendida'),
          ],
          if (showRolePicker) ...[
            const SizedBox(height: ClinicalSpacing.item),
            _RoleGrantPicker(
              membershipId: member.membershipId,
              organizationId: this.context.organizationId,
              roles: grantableRoles,
            ),
          ],
          if (roleRows.isNotEmpty) ...[
            const SizedBox(
              width: double.infinity,
              child: Padding(
                padding: EdgeInsets.only(
                  top: ClinicalSpacing.section,
                  bottom: ClinicalSpacing.compact,
                ),
                child: ClinicalSectionTitle('Roles asignados'),
              ),
            ),
            for (final assignment in roleRows)
              ListTile(
                dense: true,
                title: Text(assignment.roleName),
                subtitle: Text(_roleAssignmentHistory(assignment)),
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
                                      organizationId:
                                          this.context.organizationId,
                                      assignmentId: assignment.assignmentId,
                                      attempt: attempt,
                                    ),
                              ),
                        )
                        : null,
              ),
          ],
          if (canManage) ...[
            if (roleRows.isNotEmpty && !showRolePicker)
              const SizedBox(height: ClinicalSpacing.item),
            SizedBox(
              height:
                  showRolePicker
                      ? ClinicalSpacing.compact
                      : ClinicalSpacing.item,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
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
            ),
          ],
        ],
      ),
    );
  }
}

String _roleAssignmentHistory(IamRoleAssignment assignment) {
  final assigned = formatClinicalDateTime(assignment.validFrom);
  final revokedAt = assignment.revokedAt;
  if (revokedAt != null) {
    return 'Asignado el $assigned\nRevocado el ${formatClinicalDateTime(revokedAt)}';
  }
  final validUntil = assignment.validUntil;
  if (validUntil != null &&
      !validUntil.toUtc().isAfter(DateTime.now().toUtc())) {
    return 'Asignado el $assigned\nFinalizada el ${formatClinicalDateTime(validUntil)}';
  }
  return 'Asignado el $assigned';
}

/// Selector de rol. Descarta la selección cuando el rol concedido
/// deja de ofrecerse, para no dejar el control apuntando a un valor ausente.
class _RoleGrantPicker extends ConsumerStatefulWidget {
  const _RoleGrantPicker({
    required this.membershipId,
    required this.organizationId,
    required this.roles,
  });

  final String membershipId;
  final String organizationId;
  final List<IamRole> roles;

  @override
  ConsumerState<_RoleGrantPicker> createState() => _RoleGrantPickerState();
}

class _RoleGrantPickerState extends ConsumerState<_RoleGrantPicker> {
  String? _roleId;

  @override
  void didUpdateWidget(covariant _RoleGrantPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = _roleId;
    if (selected != null && !widget.roles.any((role) => role.id == selected)) {
      _roleId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _roleId;
    return AnchoredSelector<String>(
      key: ValueKey('role-${widget.membershipId}'),
      selectedValue:
          selected != null && widget.roles.any((role) => role.id == selected)
              ? selected
              : null,
      labelText: 'Seleccionar rol',
      options: [
        for (final role in widget.roles)
          AnchoredSelectorOption(value: role.id, label: role.name),
      ],
      onSelected: (roleId) {
        setState(() => _roleId = roleId);
        _mutate(
          context,
          ref,
          (attempt) => ref
              .read(iamRepositoryProvider)
              .grantRole(
                organizationId: widget.organizationId,
                membershipId: widget.membershipId,
                roleId: roleId,
                attempt: attempt,
              ),
          usesValidFrom: true,
        );
      },
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
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder:
        (sheetContext) => _CreateUserSheet(
          parentContext: context,
          organizationId: iam.organizationId,
          roles: roles,
        ),
  );
}

class _CreateUserSheet extends ConsumerStatefulWidget {
  const _CreateUserSheet({
    required this.parentContext,
    required this.organizationId,
    required this.roles,
  });

  /// Contexto de la pantalla, para avisos fuera del panel.
  final BuildContext parentContext;
  final String organizationId;
  final List<IamRole> roles;

  @override
  ConsumerState<_CreateUserSheet> createState() => _CreateUserSheetState();
}

class _CreateUserSheetState extends ConsumerState<_CreateUserSheet> {
  final _formKey = GlobalKey<FormState>();
  final _displayName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  /// Se genera una vez por panel y se reutiliza en los reintentos para que
  /// un fallo recuperable no cree un usuario duplicado.
  final String _idempotencyKey = newIdempotencyKey();

  late String _roleId = widget.roles.first.id;
  String? _submissionError;
  var _saving = false;
  var _passwordVisible = false;
  var _discarding = false;

  /// Un panel con datos escritos no se pierde por un arrastre accidental.
  bool get _isDirty =>
      _discarding ||
      _displayName.text.isNotEmpty ||
      _email.text.isNotEmpty ||
      _password.text.isNotEmpty;

  @override
  void dispose() {
    _displayName.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _requireDisplayName(String? value) =>
      (value ?? '').trim().isEmpty ? 'Ingresa el nombre visible.' : null;

  String? _requireEmail(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'Ingresa el correo.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Ingresa un correo válido.';
    }
    return null;
  }

  String? _requirePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Ingresa la contraseña inicial.';
    if (password.length < 12) {
      return 'La contraseña debe tener al menos 12 caracteres.';
    }
    return null;
  }

  /// Cierre explícito: consulta el estado real de los campos en el momento, sin
  /// depender de un rebuild pendiente.
  void _requestClose() {
    if (_isDirty) {
      _confirmDiscard();
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Descartar los datos'),
            content: const Text('Lo que ingresaste se perderá.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Seguir editando'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Descartar'),
              ),
            ],
          ),
    );
    if (discard != true || !mounted) return;
    setState(() => _discarding = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _submissionError = null;
    });
    try {
      await ref
          .read(iamRepositoryProvider)
          .createMember(
            organizationId: widget.organizationId,
            email: _email.text.trim(),
            password: _password.text,
            displayName: _displayName.text.trim(),
            roleId: _roleId,
            idempotencyKey: _idempotencyKey,
          );
      invalidateAuthorizationAndData(ref);
      if (!mounted) return;
      Navigator.of(context).pop();
      if (widget.parentContext.mounted) {
        ScaffoldMessenger.of(
          widget.parentContext,
        ).showSnackBar(const SnackBar(content: Text('Usuario agregado.')));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _submissionError =
              'No fue posible agregar el usuario. Puedes reintentar.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_isDirty,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _confirmDiscard();
    },
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Nuevo usuario',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: ClinicalColors.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    icon: const Icon(Icons.close),
                    onPressed: _requestClose,
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _displayName,
                        decoration: clinicalInputDecoration(
                          labelText: 'Nombre visible',
                        ),
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() {}),
                        validator: _requireDisplayName,
                      ),
                      const SizedBox(height: ClinicalSpacing.item),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: clinicalInputDecoration(
                          labelText: 'Correo',
                        ),
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() {}),
                        validator: _requireEmail,
                      ),
                      const SizedBox(height: ClinicalSpacing.item),
                      TextFormField(
                        controller: _password,
                        obscureText: !_passwordVisible,
                        decoration: clinicalInputDecoration(
                          labelText: 'Contraseña inicial',
                          helperText: 'Mínimo 12 caracteres',
                          suffixIcon: IconButton(
                            tooltip:
                                _passwordVisible
                                    ? 'Ocultar contraseña'
                                    : 'Mostrar contraseña',
                            icon: Icon(
                              _passwordVisible
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            onPressed:
                                () => setState(
                                  () => _passwordVisible = !_passwordVisible,
                                ),
                          ),
                        ),
                        textInputAction: TextInputAction.done,
                        onChanged: (_) => setState(() {}),
                        validator: _requirePassword,
                      ),
                      const SizedBox(height: ClinicalSpacing.section),
                      AnchoredSelector<String>(
                        selectedValue: _roleId,
                        labelText: 'Rol inicial',
                        options: [
                          for (final role in widget.roles)
                            AnchoredSelectorOption(
                              value: role.id,
                              label: role.name,
                            ),
                        ],
                        onSelected: (value) => setState(() => _roleId = value),
                        validator:
                            (value) =>
                                value == null
                                    ? 'Selecciona el rol inicial.'
                                    : null,
                      ),
                      if (_submissionError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _submissionError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _submit,
                      child: Text(_saving ? 'Agregando…' : 'Agregar usuario'),
                    ),
                  ),
                  TextButton(
                    onPressed: _saving ? null : _requestClose,
                    child: const Text('Cancelar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
