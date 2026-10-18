import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/clinical_design_system.dart';
import '../data/model_provisioning.dart';
import 'model_setup_components.dart';
import 'model_setup_providers.dart';

class ModelManagementScreen extends ConsumerStatefulWidget {
  const ModelManagementScreen({super.key});

  @override
  ConsumerState<ModelManagementScreen> createState() =>
      _ModelManagementScreenState();
}

class _ModelManagementScreenState extends ConsumerState<ModelManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(modelSetupControllerProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(modelSetupControllerProvider);
    final controller = ref.read(modelSetupControllerProvider.notifier);
    final refreshError = ref.watch(modelSetupRefreshErrorProvider);
    return Scaffold(
      backgroundColor: ClinicalColors.canvas,
      appBar: clinicalBackAppBar(
        context,
        title: 'Dictado y redacción',
        fallbackLocation: '/settings',
        tooltip: 'Volver a Ajustes',
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ClinicalSpacing.page),
          children: [
            const Text(
              'Administra los modelos instalados en este dispositivo.',
            ),
            const SizedBox(height: ClinicalSpacing.section),
            if (refreshError)
              Column(
                children: [
                  const Text(
                    'No se pudo comprobar el estado de la descarga. Inténtalo de nuevo.',
                  ),
                  TextButton(
                    onPressed: controller.refresh,
                    child: const Text('Reintentar'),
                  ),
                ],
              )
            else if (tasks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Comprobando…'),
                  ],
                ),
              )
            else
              for (final task in tasks) ...[
                ModelSetupCard(
                  task: task,
                  busy: controller.isBusy,
                  actions: ModelManagementCardActions(
                    onVerify: () => controller.verify(task.model),
                    onClean: () => ModelManagementOperations.confirmClean(
                      context,
                      ref,
                      task,
                    ),
                    onInstall: () => controller.install(task.model),
                    busy: controller.isBusy,
                    canClean: task.status == ModelStatus.ready,
                  ),
                ),
                const SizedBox(height: ClinicalSpacing.item),
              ],
          ],
        ),
      ),
    );
  }
}

class ModelManagementOperations {
  static Future<void> confirmClean(
    BuildContext context,
    WidgetRef ref,
    ModelTask task,
  ) async {
    final choice = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Limpiar ${task.title}?'),
        content: const Text(
          'Se eliminarán los archivos locales. Para volver a instalar el modelo se requiere conexión a internet. ¿Quieres descargarlo después de limpiar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Limpiar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Limpiar y volver a descargar'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    final controller = ref.read(modelSetupControllerProvider.notifier);
    await controller.clean(task.model);
    if (!context.mounted) return;
    if (ref.read(modelCleanBlockedProvider)) {
      ref.read(modelCleanBlockedProvider.notifier).state = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cierra editor para reparar el modelo')),
      );
      return;
    }
    final cleaned = ref
        .read(modelSetupControllerProvider)
        .any(
          (current) =>
              current.model == task.model &&
              current.status == ModelStatus.missing,
        );
    if (cleaned && choice) await controller.install(task.model);
  }
}
