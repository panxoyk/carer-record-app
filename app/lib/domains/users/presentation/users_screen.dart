import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../practitioner/domain/entities/practitioner.dart';
import '../../practitioner/presentation/practitioner_providers.dart';

typedef PractitionerUpdate =
    ({PractitionerRole? role, PractitionerStatus? status});

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final practitioners = ref.watch(practitionersProvider);
    final currentUserId = ref.watch(sessionProvider)?.user.id;
    Future<void> update(Practitioner user, PractitionerUpdate changes) async {
      await ref
          .read(practitionerRepositoryProvider)
          .update(id: user.id, role: changes.role, status: changes.status);
      ref.invalidate(practitionersProvider);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de usuarios'),
        leading: IconButton(
          tooltip: 'Volver',
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context, ref),
        icon: const Icon(Icons.person_add),
        label: const Text('Crear usuario'),
      ),
      body: practitioners.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (_, __) => const Center(
              child: Text('No fue posible cargar los usuarios.'),
            ),
        data:
            (users) => ListView(
              children: [
                for (final user in users.where(
                  (user) => user.id != currentUserId,
                ))
                  ListTile(
                    title: Text(user.displayName),
                    subtitle: Text('${user.role.name} · ${user.status.name}'),
                    trailing: PopupMenuButton<PractitionerUpdate>(
                      onSelected: (value) => update(user, value),
                      itemBuilder:
                          (_) => [
                            const PopupMenuItem(
                              value: (
                                role: null,
                                status: PractitionerStatus.active,
                              ),
                              child: Text('Activar'),
                            ),
                            const PopupMenuItem(
                              value: (
                                role: null,
                                status: PractitionerStatus.suspended,
                              ),
                              child: Text('Suspender'),
                            ),
                            for (final role in PractitionerRole.values)
                              PopupMenuItem(
                                value: (role: role, status: null),
                                child: Text('Rol: ${role.name}'),
                              ),
                          ],
                    ),
                  ),
              ],
            ),
      ),
    );
  }
}

Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  var role = PractitionerRole.technician;
  await showDialog<void>(
    context: context,
    builder:
        (dialogContext) => StatefulBuilder(
          builder:
              (_, setState) => AlertDialog(
                title: const Text('Crear usuario'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: name,
                        decoration: const InputDecoration(
                          labelText: 'Nombre visible',
                        ),
                      ),
                      TextField(
                        controller: email,
                        decoration: const InputDecoration(labelText: 'Correo'),
                      ),
                      TextField(
                        controller: password,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Contraseña inicial',
                        ),
                      ),
                      DropdownButtonFormField<PractitionerRole>(
                        value: role,
                        items: [
                          for (final item in PractitionerRole.values)
                            DropdownMenuItem(
                              value: item,
                              child: Text(item.name),
                            ),
                        ],
                        onChanged: (value) => setState(() => role = value!),
                        decoration: const InputDecoration(labelText: 'Rol'),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      await ref
                          .read(practitionerRepositoryProvider)
                          .create(
                            email: email.text,
                            password: password.text,
                            displayName: name.text,
                            role: role,
                          );
                      ref.invalidate(practitionersProvider);
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    },
                    child: const Text('Crear'),
                  ),
                ],
              ),
        ),
  );
  email.dispose();
  password.dispose();
  name.dispose();
}
