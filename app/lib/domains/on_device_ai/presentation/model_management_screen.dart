import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/clinical_design_system.dart';
import '../../../core/design_system/clinical_toast.dart';
import '../presentation/models/model_task.dart';
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
    final cleanBlocked = ref.watch(modelCleanBlockedProvider);
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
            if (cleanBlocked) ...[
              const Text(
                'Cierra el editor antes de limpiar el modelo.',
                key: Key('model-clean-blocked'),
                semanticsLabel: 'Cierra el editor antes de limpiar el modelo.',
              ),
              const SizedBox(height: ClinicalSpacing.item),
            ],
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
                    onVerify: () => _verify(task),
                    onClean: () => ModelManagementOperations.confirmClean(
                      context,
                      ref,
                      task,
                    ),
                    onInstall: () => _install(task),
                    busy: controller.isBusy,
                    canClean: task.status == ModelStatus.ready,
                    canInstall:
                        task.status == ModelStatus.missing ||
                        task.status == ModelStatus.failed,
                  ),
                ),
                const SizedBox(height: ClinicalSpacing.item),
              ],
          ],
        ),
      ),
    );
  }

  Future<void> _verify(ModelTask task) async {
    final controller = ref.read(modelSetupControllerProvider.notifier);
    if (controller.isBusy || ref.read(modelSetupRefreshErrorProvider)) return;
    await controller.verify(task.model);
    if (!mounted) return;
    final result = ref
        .read(modelSetupControllerProvider)
        .where((item) => item.model == task.model)
        .firstOrNull;
    if (result?.status == ModelStatus.ready) {
      ClinicalToast.success(
        context,
        message: '${task.title}: verificación completada.',
      );
    } else if (result?.status == ModelStatus.missing) {
      ClinicalToast.failure(
        context,
        message: '${task.title}: la verificación falló; vuelve a descargarlo.',
      );
    }
    // Persistent task errors remain visible in the card; do not repeat them here.
  }

  Future<void> _install(ModelTask task) async {
    final controller = ref.read(modelSetupControllerProvider.notifier);
    if (controller.isBusy || ref.read(modelSetupRefreshErrorProvider)) return;
    await controller.install(task.model);
    if (!mounted) return;
    final result = ref
        .read(modelSetupControllerProvider)
        .where((item) => item.model == task.model)
        .firstOrNull;
    if (result?.status == ModelStatus.ready) {
      ClinicalToast.success(
        context,
        message: '${task.title}: instalación lista.',
      );
    }
    // Installation failures have persistent inline detail; no duplicate toast.
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
    if (!context.mounted) return;
    final controller = ref.read(modelSetupControllerProvider.notifier);
    if (controller.isBusy || ref.read(modelSetupRefreshErrorProvider)) return;
    ref.read(modelCleanBlockedProvider.notifier).state = false;
    await controller.clean(task.model);
    if (!context.mounted) return;
    if (ref.read(modelCleanBlockedProvider)) {
      ClinicalToast.failure(context, message: 'No se pudo limpiar el modelo.');
      return;
    }
    final cleaned = ref
        .read(modelSetupControllerProvider)
        .any(
          (current) =>
              current.model == task.model &&
              current.status == ModelStatus.missing,
        );
    if (!cleaned) {
      final result = ref
          .read(modelSetupControllerProvider)
          .where((item) => item.model == task.model)
          .firstOrNull;
      if (result?.status == ModelStatus.failed) return;
      return;
    }
    if (!choice) {
      ClinicalToast.success(
        context,
        message: '${task.title}: modelo eliminado.',
      );
      return;
    }
    await controller.install(task.model);
    if (!context.mounted) return;
    final result = ref
        .read(modelSetupControllerProvider)
        .where((item) => item.model == task.model)
        .firstOrNull;
    if (result?.status == ModelStatus.ready) {
      ClinicalToast.success(
        context,
        message: '${task.title}: instalación lista.',
      );
    }
  }
}
