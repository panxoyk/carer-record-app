import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/presentation/auth_providers.dart';

final practitionersProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final response = await ref
      .watch(supabaseClientProvider)
      .functions
      .invoke('manage-practitioners', body: {'action': 'list'});
  return List<Map<String, dynamic>>.from(response.data as List);
});

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final practitioners = ref.watch(practitionersProvider);
    Future<void> update(
      Map<String, dynamic> user,
      Map<String, String> changes,
    ) async {
      await ref
          .read(supabaseClientProvider)
          .functions
          .invoke(
            'manage-practitioners',
            body: {'action': 'update', 'id': user['id'], ...changes},
          );
      ref.invalidate(practitionersProvider);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Gestión de usuarios')),
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
                for (final user in users)
                  ListTile(
                    title: Text(user['display_name'] as String),
                    subtitle: Text('${user['role']} · ${user['status']}'),
                    trailing: PopupMenuButton<String>(
                      onSelected:
                          (value) => update(
                            user,
                            value.startsWith('role:')
                                ? {'role': value.substring(5)}
                                : {'status': value},
                          ),
                      itemBuilder:
                          (_) => [
                            const PopupMenuItem(
                              value: 'active',
                              child: Text('Activar'),
                            ),
                            const PopupMenuItem(
                              value: 'suspended',
                              child: Text('Suspender'),
                            ),
                            for (final role in [
                              'administrator',
                              'physician',
                              'nurse',
                              'technician',
                            ])
                              PopupMenuItem(
                                value: 'role:$role',
                                child: Text('Rol: $role'),
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
  var role = 'technician';
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
                      DropdownButtonFormField<String>(
                        value: role,
                        items: [
                          for (final item in [
                            'administrator',
                            'physician',
                            'nurse',
                            'technician',
                          ])
                            DropdownMenuItem(value: item, child: Text(item)),
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
                          .read(supabaseClientProvider)
                          .functions
                          .invoke(
                            'manage-practitioners',
                            body: {
                              'action': 'create',
                              'email': email.text,
                              'password': password.text,
                              'displayName': name.text,
                              'role': role,
                            },
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
