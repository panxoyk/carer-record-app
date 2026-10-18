import 'package:flutter/material.dart';

import '../../../core/design_system/clinical_design_system.dart';
import '../../../core/design_system/clinical_page_title.dart';
import '../presentation/models/model_task.dart';

class ModelSetupCard extends StatelessWidget {
  const ModelSetupCard({
    super.key,
    required this.task,
    this.actions,
    required this.busy,
  });

  final ModelTask task;
  final Widget? actions;
  final bool busy;

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
              ModelSetupStatusBadge(task: task),
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
          if (actions != null) ...[
            const SizedBox(height: ClinicalSpacing.item),
            actions!,
          ],
          if (installing) ...[
            const SizedBox(height: ClinicalSpacing.item),
            LinearProgressIndicator(
              value: task.stage == 'descargando' ? task.fraction : null,
              minHeight: 6,
              borderRadius: BorderRadius.circular(ClinicalRadii.pill),
            ),
            const SizedBox(height: ClinicalSpacing.compact),
            Text(
              task.stage == 'descargando' &&
                      task.receivedBytes != null &&
                      task.totalBytes != null
                  ? '${task.stageLabel} · ${_formatBytes(task.receivedBytes!)} / ${_formatBytes(task.totalBytes!)} · ${((task.fraction ?? 0) * 100).toStringAsFixed(0)} %\n${task.eta == null ? 'Calculando tiempo restante…' : 'Tiempo restante: ${_formatEta(task.eta!)}'}'
                  : task.stageLabel,
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

class ModelSetupFooter extends StatelessWidget {
  const ModelSetupFooter({
    super.key,
    required this.pendingBytes,
    required this.busy,
    required this.allReady,
    required this.onStart,
    required this.continueAction,
    required this.failed,
  });
  final int pendingBytes;
  final bool busy;
  final bool allReady;
  final VoidCallback onStart;
  final VoidCallback? continueAction;
  final bool failed;
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
              'Descargar ${mb >= 1000 ? '${(mb / 1000).toStringAsFixed(2)} GB' : '${mb.toStringAsFixed(0)} MB'}',
            ),
          ),
        if (busy)
          FilledButton(
            onPressed: null,
            child: Text(failed ? 'Operación en curso…' : 'Preparando dictado…'),
          ),
        if (continueAction != null) ...[
          const SizedBox(height: ClinicalSpacing.compact),
          TextButton(
            onPressed: busy ? null : continueAction,
            child: Text(
              failed
                  ? 'Ahora no'
                  : allReady
                  ? 'Continuar'
                  : 'Ahora no',
            ),
          ),
        ],
      ],
    );
  }
}

String _formatBytes(int bytes) => bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).toStringAsFixed(0)} KB';

String _formatEta(Duration eta) => eta.inMinutes > 0
    ? '${eta.inMinutes} min ${eta.inSeconds.remainder(60)} s'
    : '${eta.inSeconds} s';

class ModelManagementCardActions extends StatelessWidget {
  const ModelManagementCardActions({
    required this.onVerify,
    required this.onClean,
    required this.onInstall,
    required this.busy,
    required this.canClean,
    required this.canInstall,
    super.key,
  });
  final VoidCallback onVerify;
  final VoidCallback onClean;
  final VoidCallback onInstall;
  final bool busy;
  final bool canClean;
  final bool canInstall;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: ClinicalSpacing.compact,
    children: [
      if (canInstall)
        FilledButton(
          onPressed: busy ? null : onInstall,
          child: const Text('Descargar'),
        ),
      OutlinedButton(
        onPressed: busy ? null : onVerify,
        child: const Text('Comprobar descarga'),
      ),
      OutlinedButton(
        onPressed: busy || !canClean ? null : onClean,
        child: const Text('Limpiar'),
      ),
    ],
  );
}

class ModelSetupDownloadAction extends StatelessWidget {
  const ModelSetupDownloadAction({
    required this.busy,
    required this.onDownload,
    super.key,
  });

  final bool busy;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) => FilledButton.tonal(
    onPressed: busy ? null : onDownload,
    child: const Text('Descargar'),
  );
}

class ModelSetupStatusBadge extends StatelessWidget {
  const ModelSetupStatusBadge({super.key, required this.task});

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
