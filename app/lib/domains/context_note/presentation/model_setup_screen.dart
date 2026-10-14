import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/clinical_design_system.dart';
import '../../../core/design_system/clinical_page_title.dart';
import '../data/model_provisioning.dart';
import 'model_setup_providers.dart';

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
    // A device that already has the weights must not be made to tap through a
    // screen about downloading them.
    if (controller.allReady && mounted) context.go('/');
  }

  void _start() {
    ref.read(modelSetupControllerProvider.notifier).installAll();
  }

  void _continue() {
    if (context.mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(modelSetupControllerProvider);
    final controller = ref.read(modelSetupControllerProvider.notifier);

    return Scaffold(
      backgroundColor: ClinicalColors.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(ClinicalSpacing.page),
              children: [
                const ClinicalPageTitle(
                  'Preparar el dispositivo',
                  subtitle:
                      'Dos modelos se ejecutan dentro del teléfono: uno '
                      'transcribe la voz de los hitos y otro ayuda a redactar. '
                      'Se descargan una sola vez y a partir de ahí todo '
                      'funciona sin conexión.',
                ),
                if (tasks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  for (final task in tasks) ...[
                    _ModelCard(task: task),
                    const SizedBox(height: ClinicalSpacing.item),
                  ],
                  const SizedBox(height: ClinicalSpacing.section),
                  _Footer(
                    pendingBytes: controller.pendingBytes,
                    busy: controller.isBusy,
                    allReady: controller.allReady,
                    onStart: _start,
                    onContinue: _continue,
                  ),
                  const SizedBox(height: ClinicalSpacing.compact),
                  const Text(
                    'Los pesos se verifican por checksum antes de usarse. '
                    'Ninguna descarga contiene información clínica.',
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

class _ModelCard extends StatelessWidget {
  const _ModelCard({required this.task});

  final ModelTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installing = task.status == ModelStatus.installing;
    final ready = task.status == ModelStatus.ready;

    return ClinicalContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                task.model == LocalModel.speech
                    ? Icons.graphic_eq
                    : Icons.auto_fix_high,
                color: ready
                    ? ClinicalColors.mintText
                    : ClinicalColors.secondary,
              ),
              const SizedBox(width: ClinicalSpacing.item),
              Expanded(
                child: Text(task.title, style: theme.textTheme.titleMedium),
              ),
              _StatusBadge(task: task),
            ],
          ),
          const SizedBox(height: ClinicalSpacing.compact),
          Text(
            task.purpose,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ClinicalColors.secondary,
            ),
          ),
          const SizedBox(height: ClinicalSpacing.item),
          Text(
            '${task.version} · ${task.sizeLabel} · ${task.license}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: ClinicalColors.tertiary,
            ),
          ),
          if (installing) ...[
            const SizedBox(height: ClinicalSpacing.item),
            LinearProgressIndicator(
              value: task.fraction,
              minHeight: 6,
              borderRadius: BorderRadius.circular(ClinicalRadii.pill),
            ),
            const SizedBox(height: ClinicalSpacing.compact),
            Text(
              task.fraction == null
                  ? task.stageLabel
                  : '${task.stageLabel} · '
                        '${(task.fraction! * 100).toStringAsFixed(0)} %',
              style: theme.textTheme.bodySmall?.copyWith(
                color: ClinicalColors.secondary,
              ),
            ),
          ],
          if (task.status == ModelStatus.failed) ...[
            const SizedBox(height: ClinicalSpacing.item),
            Text(
              task.error ?? 'No se pudo instalar.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: ClinicalColors.destructive,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.task});

  final ModelTask task;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (task.status) {
      ModelStatus.ready => ('Listo', ClinicalColors.mintText),
      ModelStatus.installing => (task.stageLabel, ClinicalColors.secondary),
      ModelStatus.failed => ('Error', ClinicalColors.destructive),
      ModelStatus.checking => ('Comprobando', ClinicalColors.tertiary),
      ModelStatus.missing => ('Pendiente', ClinicalColors.tertiary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ClinicalRadii.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.pendingBytes,
    required this.busy,
    required this.allReady,
    required this.onStart,
    required this.onContinue,
  });

  final int pendingBytes;
  final bool busy;
  final bool allReady;
  final VoidCallback onStart;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final mb = pendingBytes / (1024 * 1024);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!allReady && !busy)
          FilledButton(
            onPressed: onStart,
            child: Text(
              pendingBytes <= 0
                  ? 'Comprobar de nuevo'
                  : 'Descargar ${mb >= 1000 ? '${(mb / 1000).toStringAsFixed(2)} GB' : '${mb.toStringAsFixed(0)} MB'}',
            ),
          ),
        if (busy)
          const FilledButton(onPressed: null, child: Text('Descargando…')),
        const SizedBox(height: ClinicalSpacing.compact),
        // Skipping is always available: without the models the record still
        // works, it just cannot dictate or suggest rewrites.
        TextButton(
          onPressed: busy ? null : onContinue,
          child: const Text('Continuar sin los modelos'),
        ),
      ],
    );
  }
}
