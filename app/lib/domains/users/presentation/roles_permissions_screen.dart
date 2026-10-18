import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/clinical_design_system.dart';
import '../../../core/design_system/clinical_toast.dart';
import '../../../core/design_system/anchored_selector.dart';
import '../../institutional/domain/iam_entities.dart';
import '../../institutional/presentation/iam_providers.dart';
import '../../../core/session/authorization_refresh.dart';
import 'controllers/role_permissions_controller.dart';

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
        error: (_, __) => _retry(
          () => ref.read(authorizationRefreshProvider)(),
          'No fue posible validar el acceso.',
        ),
        data: (context) {
          if (context == null ||
              !context.allows('iam.role.read') ||
              !context.allows('iam.role.manage')) {
            return const Center(child: Text('Acceso no disponible.'));
          }
          return _RolePermissionsBody(
            key: ValueKey('${context.organizationId}:${context.profileId}'),
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
      error: (_, __) => _retry(
        () => ref.invalidate(iamRolesProvider),
        'No fue posible cargar los roles.',
      ),
      data: (items) => catalog.when(
        skipLoadingOnRefresh: false,
        skipError: false,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _retry(
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
  /// El texto vive en el State y no en el campo: cambiar de rol remonta el
  /// editor, y el campo debe conservar lo escrito y el foco.
  final _permissionSearchController = TextEditingController();
  late RolePermissionsController _controller;
  String? get _roleId => _controller.selectedRoleId;
  Set<String> get _draft => _controller.draft;
  bool get _saving => _controller.busy;
  int _roleSelectionRevision = 0;
  RolePermissionsSaveSnapshot? _failedSnapshot;
  String? _saveError;
  var _permissionQuery = '';

  @override
  void initState() {
    super.initState();
    _controller = RolePermissionsController(
      administration: ref.read(iamAdministrationProvider),
      attemptFactory: ref.read(iamOperationAttemptFactoryProvider),
      refreshAuthorization: () => ref.read(authorizationRefreshProvider)(),
      organizationId: widget.iamContext.organizationId,
      roles: widget.roles,
    )..setCatalog(widget.catalog);
    _controller.addListener(_controllerChanged);
  }

  void _controllerChanged() {
    if (!mounted) return;
    final failedSnapshot = _failedSnapshot;
    if (!_controller.busy &&
        failedSnapshot != null &&
        _controller.retrySnapshot != failedSnapshot) {
      _failedSnapshot = null;
      _saveError = null;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _permissionSearchController.dispose();
    _controller.removeListener(_controllerChanged);
    _controller.dispose();
    super.dispose();
  }

  bool get _dirty => _controller.dirty;

  @override
  Widget build(BuildContext context) =>
      _ready(context, widget.roles, widget.catalog);

  Widget _ready(
    BuildContext context,
    List<IamRole> roles,
    List<IamPermission> catalog,
  ) {
    final role = roles.where((item) => item.id == _roleId).firstOrNull;
    final hidden = role != null && _controller.hasHiddenPermissions;
    if (roles.isEmpty) {
      return const Center(child: Text('No hay roles ordinarios activos.'));
    }
    final query = _permissionQuery.trim().toLowerCase();
    final visible = catalog.where((permission) {
      if (query.isEmpty) return true;
      return permission.code.toLowerCase().contains(query) ||
          permission.family.toLowerCase().contains(query) ||
          permission.description.toLowerCase().contains(query);
    }).toList();
    final groups = <String, List<IamPermission>>{};
    for (final permission in visible) {
      (groups[permission.family] ??= []).add(permission);
    }
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_saveError != null) ...[
                Text(
                  _saveError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                if (_failedSnapshot != null)
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => _save(
                            context,
                            retrySnapshot: _failedSnapshot,
                            alreadyConfirmed: true,
                          ),
                    child: const Text('Reintentar guardado'),
                  ),
              ],
              AnchoredSelector<String>(
                key: ValueKey(_roleSelectionRevision),
                selectedValue: role?.id,
                labelText: 'Rol',
                decoration: clinicalInputDecoration(labelText: 'Rol'),
                options: [
                  for (final item in roles)
                    AnchoredSelectorOption(value: item.id, label: item.name),
                ],
                onSelected: (id) => _selectRole(context, id, roles),
              ),
              if (role != null) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('permission-search'),
                  controller: _permissionSearchController,
                  decoration: clinicalInputDecoration(
                    hintText: 'Nombre o descripción',
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (value) =>
                      setState(() => _permissionQuery = value),
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
                  Text(
                    entry.key,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final permission in entry.value)
                    CheckboxListTile(
                      value: _draft.contains(permission.code),
                      title: Text(permission.code),
                      subtitle: Text(permission.description),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: _saving
                          ? null
                          : (checked) => _controller.setPermission(
                              permission.code,
                              checked == true,
                            ),
                    ),
                ],
                if (visible.isEmpty)
                  const ListTile(
                    title: Text('Ningún permiso coincide con la búsqueda.'),
                  ),
              ],
            ],
          ),
        ),
        if (role != null)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving || !_dirty || hidden
                      ? null
                      : () => _save(context),
                  child: Text(_saving ? 'Guardando…' : 'Guardar'),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _selectRole(
    BuildContext context,
    String? id,
    List<IamRole> roles,
  ) async {
    if (id == null || id == _roleId) return;
    if (_dirty &&
        !await _confirm(context, '¿Descartar los cambios pendientes?')) {
      if (mounted) setState(() => _roleSelectionRevision++);
      return;
    }
    if (!mounted) return;
    final next = roles.where((role) => role.id == id).firstOrNull;
    if (next == null) return;
    _controller.selectRole(id);
    setState(() => _roleSelectionRevision++);
  }

  Future<void> _save(
    BuildContext context, {
    RolePermissionsSaveSnapshot? retrySnapshot,
    bool alreadyConfirmed = false,
  }) async {
    final selected = _roleId;
    if (selected == null) return;
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
    AdminOperationResult? result;
    RolePermissionsSaveSnapshot? failedSnapshot;
    try {
      setState(() {
        _saveError = null;
      });
      result = await _controller.save(retry: retrySnapshot);
    } catch (_) {
      failedSnapshot = _controller.retrySnapshot;
    }
    if (!context.mounted) return;
    if (failedSnapshot != null) {
      setState(() {
        _failedSnapshot = failedSnapshot;
        _saveError = 'No se pudo confirmar el guardado. El resultado podría haberse aplicado; reintenta el mismo cambio para verificarlo.';
      });
      ClinicalToast.failure(
        context,
        message: 'No se pudo confirmar el guardado de los permisos.',
      );
      return;
    }
    if (result == null) return;
    if (result.success) {
      setState(() {
        _failedSnapshot = null;
        _saveError = null;
      });
      ClinicalToast.success(context, message: 'Permisos actualizados.');
    } else {
      setState(() {
        _failedSnapshot = null;
        _saveError = _safeResult(result!.code);
      });
      ClinicalToast.failure(
        context,
        message: 'No se pudo guardar la composición de permisos.',
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
      builder: (context) => AlertDialog(
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
