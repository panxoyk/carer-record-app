import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/design_system/clinical_design_system.dart';
import '../../institutional/data/iam_models.dart';
import '../../institutional/data/iam_repository.dart';
import '../../institutional/presentation/iam_providers.dart';

/// Isolated role-composition view; navigation is intentionally owned by callers.
class RolesPermissionsScreen extends ConsumerWidget {
  const RolesPermissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iam = ref.watch(iamContextProvider);
    return Scaffold(
      appBar: clinicalBackAppBar(
        context,
        title: 'Gestión de roles y permisos',
        fallbackLocation: '/settings',
        tooltip: 'Volver a Ajustes',
      ),
      body: iam.when(
        skipLoadingOnRefresh: false,
        skipError: false,
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (_, __) => _retry(
              () => invalidateAuthorizationAndData(ref),
              'No fue posible validar el acceso.',
            ),
        data: (context) {
          if (context == null ||
              !context.allows('iam.role.read') ||
              !context.allows('iam.role.manage')) {
            return const Center(child: Text('Acceso no disponible.'));
          }
          return _RolePermissionsBody(
            key: ValueKey(context.organizationId),
            iamContext: context,
          );
        },
      ),
    );
  }
}

class _RolePermissionsBody extends ConsumerWidget {
  const _RolePermissionsBody({super.key, required this.iamContext});
  final IamContext iamContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roles = ref.watch(iamRolesProvider);
    final catalog = ref.watch(iamDelegablePermissionsProvider);
    return roles.when(
      skipLoadingOnRefresh: false,
      skipError: false,
      loading: () => const Center(child: CircularProgressIndicator()),
      error:
          (_, __) => _retry(
            () => ref.invalidate(iamRolesProvider),
            'No fue posible cargar los roles.',
          ),
      data:
          (items) => catalog.when(
            skipLoadingOnRefresh: false,
            skipError: false,
            loading: () => const Center(child: CircularProgressIndicator()),
            error:
                (_, __) => _retry(
                  () => ref.invalidate(iamDelegablePermissionsProvider),
                  'No fue posible cargar el catálogo.',
                ),
            data: (permissions) {
              final ordinary = items.where((role) => !role.protected).toList();
              final fingerprint = [
                ...ordinary.map(
                  (role) =>
                      '${role.id}:${role.name}:${role.description}:${role.permissions.toList()..sort()}',
                ),
                ...permissions.map(
                  (item) => '${item.code}:${item.family}:${item.description}',
                ),
              ].join('|');
              return _RoleEditor(
                key: ValueKey('${iamContext.organizationId}:$fingerprint'),
                iamContext: iamContext,
                roles: ordinary,
                catalog: permissions,
              );
            },
          ),
    );
  }
}

class _RoleEditor extends ConsumerStatefulWidget {
  const _RoleEditor({
    super.key,
    required this.iamContext,
    required this.roles,
    required this.catalog,
  });
  final IamContext iamContext;
  final List<IamRole> roles;
  final List<IamPermission> catalog;

  @override
  ConsumerState<_RoleEditor> createState() => _RoleEditorState();
}

class _RoleEditorState extends ConsumerState<_RoleEditor> {
  String? _roleId;
  Set<String> _draft = {};
  Set<String> _initial = {};
  bool _saving = false;
  var _permissionQuery = '';

  bool get _dirty =>
      !_draft.containsAll(_initial) || !_initial.containsAll(_draft);

  @override
  Widget build(BuildContext context) =>
      _ready(context, widget.roles, widget.catalog);

  Widget _ready(
    BuildContext context,
    List<IamRole> roles,
    List<IamPermission> catalog,
  ) {
    final role = roles.where((item) => item.id == _roleId).firstOrNull;
    final catalogCodes = catalog.map((permission) => permission.code).toSet();
    final hidden = role != null && !catalogCodes.containsAll(role.permissions);
    if (roles.isEmpty) {
      return const Center(child: Text('No hay roles ordinarios activos.'));
    }
    final query = _permissionQuery.trim().toLowerCase();
    final visible =
        catalog.where((permission) {
          if (query.isEmpty) return true;
          return permission.code.toLowerCase().contains(query) ||
              permission.family.toLowerCase().contains(query) ||
              permission.description.toLowerCase().contains(query);
        }).toList();
    final groups = <String, List<IamPermission>>{};
    for (final permission in visible) {
      (groups[permission.family] ??= []).add(permission);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          value: role?.id,
          decoration: const InputDecoration(labelText: 'Rol'),
          items: [
            for (final item in roles)
              DropdownMenuItem(value: item.id, child: Text(item.name)),
          ],
          onChanged: _saving ? null : (id) => _selectRole(context, id, roles),
        ),
        if (role != null) ...[
          const SizedBox(height: 8),
          Text(role.description),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Buscar permisos',
              helperText: 'Busca por nombre, familia o descripción.',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => _permissionQuery = value),
          ),
          if (hidden)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'El rol contiene permisos no disponibles para esta edición. Recarga o solicita revisión antes de continuar.',
              ),
            ),
          for (final entry in groups.entries) ...[
            const SizedBox(height: 16),
            Text(entry.key, style: Theme.of(context).textTheme.titleMedium),
            for (final permission in entry.value)
              CheckboxListTile(
                value: _draft.contains(permission.code),
                title: Text(permission.code),
                subtitle: Text(permission.description),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged:
                    _saving
                        ? null
                        : (checked) => setState(() {
                          checked == true
                              ? _draft.add(permission.code)
                              : _draft.remove(permission.code);
                        }),
              ),
          ],
          if (visible.isEmpty)
            const ListTile(
              title: Text('Ningún permiso coincide con la búsqueda.'),
            ),
          FilledButton(
            onPressed:
                _saving || !_dirty || hidden ? null : () => _save(context),
            child: Text(_saving ? 'Guardando…' : 'Guardar'),
          ),
        ],
      ],
    );
  }

  void _loadRole(IamRole role) {
    _initial = Set<String>.from(role.permissions);
    _draft = Set<String>.from(role.permissions);
  }

  Future<void> _selectRole(
    BuildContext context,
    String? id,
    List<IamRole> roles,
  ) async {
    if (id == null || id == _roleId) return;
    if (_dirty &&
        !await _confirm(context, '¿Descartar los cambios pendientes?')) {
      return;
    }
    if (!mounted) return;
    final next = roles.where((role) => role.id == id).firstOrNull;
    if (next == null) return;
    setState(() {
      _roleId = id;
      _loadRole(next);
    });
  }

  Future<void> _save(
    BuildContext context, {
    ({AdminOperationAttempt attempt, Set<String> permissions, String roleId})?
    retrySnapshot,
    bool alreadyConfirmed = false,
  }) async {
    final selected = _roleId;
    if (selected == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final empty = _draft.isEmpty;
    if (!alreadyConfirmed &&
        !await _confirm(
          context,
          empty
              ? 'Vas a quitar todos los permisos de este rol. El cambio tendrá efecto inmediato. ¿Continuar?'
              : 'Vas a reemplazar todos los permisos de este rol. El cambio tendrá efecto inmediato. ¿Continuar?',
        )) {
      return;
    }
    if (!mounted) return;
    final snapshot =
        retrySnapshot ??
        (
          attempt: newAdminOperationAttempt(),
          permissions: Set<String>.from(_draft),
          roleId: selected,
        );
    setState(() {
      _saving = true;
    });
    try {
      final result = await ref
          .read(iamRepositoryProvider)
          .replaceRolePermissions(
            organizationId: widget.iamContext.organizationId,
            roleId: snapshot.roleId,
            permissions: snapshot.permissions.toList()..sort(),
            attempt: snapshot.attempt,
          );
      if (!mounted) return;
      if (result.success) {
        invalidateAuthorizationAndData(ref);
        setState(() {
          _saving = false;
          _roleId = null;
          _draft = {};
          _initial = {};
        });
        messenger.showSnackBar(
          const SnackBar(content: Text('Permisos actualizados.')),
        );
      } else {
        setState(() {
          _saving = false;
        });
        messenger.showSnackBar(
          SnackBar(content: Text(_safeResult(result.code))),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      final failedSnapshot = snapshot;
      messenger.showSnackBar(
        SnackBar(
          content: const Text('No fue posible guardar los permisos.'),
          action: SnackBarAction(
            label: 'Reintentar',
            onPressed:
                () => _save(
                  context,
                  retrySnapshot: failedSnapshot,
                  alreadyConfirmed: true,
                ),
          ),
        ),
      );
    }
  }

  String _safeResult(String code) => switch (code) {
    'denied' => 'No fue posible autorizar este cambio.',
    'permission_not_delegable' =>
      'El conjunto de permisos ya no está disponible.',
    'protected_or_missing' => 'No fue posible actualizar este rol.',
    'idempotency_conflict' =>
      'La solicitud no pudo confirmarse. Recarga antes de continuar.',
    _ => 'No fue posible actualizar los permisos.',
  };
}

Future<bool> _confirm(BuildContext context, String message) async =>
    await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Confirmar cambio'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirmar'),
              ),
            ],
          ),
    ) ??
    false;

Widget _retry(VoidCallback retry, String message) => Center(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(message),
      TextButton(onPressed: retry, child: const Text('Reintentar')),
    ],
  ),
);
