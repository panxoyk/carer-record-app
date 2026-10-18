import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/clinical_design_system.dart';
import '../../../core/design_system/clinical_page_title.dart';
import '../data/model_provisioning.dart';
import 'model_setup_providers.dart';
import 'model_setup_components.dart';

/// First-run screen that pulls the on-device weights onto the device.
///
/// The repository ships versioned manifests and no blobs, so anyone who clones
/// the project hits this screen once and ends up with a working dictation and
/// text-assistance stack. It is skippable on purpose: the clinical record is
/// fully usable without them, because a missing model only removes the dictated
/// milestone and the optional text assistance (ADR-016, ADR-017).
class ModelSetupScreen extends ConsumerStatefulWidget {
  const ModelSetupScreen({super.key});

  @override
  ConsumerState<ModelSetupScreen> createState() => _ModelSetupScreenState();
}

class _ModelSetupScreenState extends ConsumerState<ModelSetupScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred so the first frame is not blocked on disk and asset I/O.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final controller = ref.read(modelSetupControllerProvider.notifier);
    await controller.refresh();
    if (!mounted) return;
    final tasks = ref.read(modelSetupControllerProvider);
    if (tasks.any((task) => task.status == ModelStatus.failed)) {
      return;
    }
    // A device that already has the weights must not be made to tap through a
    // screen about downloading them.
    if (tasks.isNotEmpty &&
        tasks.every((task) => task.status == ModelStatus.ready) &&
        mounted) {
      context.go('/');
    }
  }

  void _start() {
    ref.read(setupAwaitingContinueProvider.notifier).state = true;
    ref.read(modelSetupControllerProvider.notifier).installAll();
  }

  void _continue() {
    ref.read(modelSetupSkippedProvider.notifier).state = true;
    ref.read(setupAwaitingContinueProvider.notifier).state = false;
    if (context.mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(modelSetupControllerProvider);
    final controller = ref.read(modelSetupControllerProvider.notifier);
    final refreshFailed = ref.watch(modelSetupRefreshErrorProvider);

    return Scaffold(
      backgroundColor: ClinicalColors.canvas,
      appBar: null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(ClinicalSpacing.page),
              children: [
                const ClinicalPageTitle(
                  'Activa el dictado y la ayuda de redacción',
                  subtitle: 'Descarga los modelos para usar estas funciones en este dispositivo.',
                ),
                if (refreshFailed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(
                      children: [
                        const Text(
                          'No se pudo comprobar el estado de la descarga. Inténtalo de nuevo.',
                        ),
                        TextButton(
                          onPressed: controller.refresh,
                          child: const Text('Reintentar'),
                        ),
                        TextButton(
                          onPressed: _continue,
                          child: const Text('Ahora no'),
                        ),
                      ],
                    ),
                  )
                else if (tasks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('Comprobando descarga…'),
                        ],
                      ),
                    ),
                  )
                else ...[
                  for (final task in tasks) ...[
                    ModelSetupCard(task: task, busy: controller.isBusy),
                    const SizedBox(height: ClinicalSpacing.item),
                  ],
                  const SizedBox(height: ClinicalSpacing.section),
                  ModelSetupFooter(
                    pendingBytes: controller.pendingBytes,
                    busy: controller.isBusy,
                    allReady: controller.allReady,
                    onStart: _start,
                    continueAction: _continue,
                    failed: tasks.any(
                      (task) => task.status == ModelStatus.failed,
                    ),
                  ),
                  const SizedBox(height: ClinicalSpacing.compact),
                  const Text(
                    'La descarga contiene solo modelos de IA, no información clínica.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: ClinicalColors.secondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
