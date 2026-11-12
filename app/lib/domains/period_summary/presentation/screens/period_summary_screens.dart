import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../../core/design_system/clinical_design_system.dart';
import '../../../on_device_ai/presentation/local_ai_providers.dart';
import '../../../patient/presentation/patient_providers.dart';
import '../../domain/period_summary.dart';
import '../controllers/period_summary_controller.dart';
import '../period_summary_providers.dart';

const _labels = {
  SummarySourceKind.contextNote: 'Notas',
  SummarySourceKind.condition: 'Diagnósticos',
  SummarySourceKind.observation: 'Observaciones',
  SummarySourceKind.medicationRequest: 'Medicaciones',
  SummarySourceKind.procedure: 'Procedimientos',
  SummarySourceKind.diagnosticReport: 'Informes',
};
const _historicalWarning =
    'Síntesis asistida: incluye la información disponible al momento de su generación. No es una nota clínica y no se actualiza automáticamente.';

class _EpisodeBody extends ConsumerWidget {
  const _EpisodeBody({required this.episode, required this.child});
  final String episode;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(periodSummaryAllowedProvider)) {
      return const Center(child: Text('No tienes acceso a esta función.'));
    }
    return ref
        .watch(patientProvider(episode))
        .when(
          skipLoadingOnRefresh: false,
          skipError: false,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
            child: TextButton(
              onPressed: () => ref.invalidate(patientProvider(episode)),
              child: const Text('Reintentar verificación del episodio'),
            ),
          ),
          data: (patient) => patient == null
              ? const Center(child: Text('Episodio no disponible.'))
              : Column(
                  children: [
                    ListTile(
                      title: Text(patient.fullName),
                      subtitle: Text(
                        'Hospitalización · ${patient.locationLabel}',
                      ),
                    ),
                    Expanded(child: child),
                  ],
                ),
        );
  }
}

class PeriodSummaryHistoryScreen extends ConsumerStatefulWidget {
  const PeriodSummaryHistoryScreen({
    super.key,
    required this.hospitalizationId,
  });
  final String hospitalizationId;
  @override
  ConsumerState<PeriodSummaryHistoryScreen> createState() => _HistoryState();
}

class _HistoryState extends ConsumerState<PeriodSummaryHistoryScreen> {
  int offset = 0;
  @override
  Widget build(BuildContext context) {
    final id = widget.hospitalizationId;
    final key = (episodeId: id, offset: offset);
    final rows = ref.watch(periodSummaryHistoryProvider(key));
    return Scaffold(
      appBar: clinicalBackAppBar(context, title: 'Mis resúmenes'),
      body: _EpisodeBody(
        episode: id,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: () =>
                    context.push('/hospitalizations/$id/summaries/new'),
                icon: const Icon(Icons.add),
                label: const Text('Generar resumen'),
              ),
            ),
            Expanded(
              child: rows.when(
                skipLoadingOnRefresh: false,
                skipError: false,
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => Center(
                  child: TextButton(
                    onPressed: () =>
                        ref.invalidate(periodSummaryHistoryProvider(key)),
                    child: const Text('Reintentar carga de resúmenes'),
                  ),
                ),
                data: (list) => list.isEmpty
                    ? const Center(
                        child: Text(
                          'Aún no has generado resúmenes para esta hospitalización.',
                        ),
                      )
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, index) {
                          final item = list[index];
                          return ListTile(
                            title: Text(_range(item.window)),
                            subtitle: Text(
                              'Generado: ${_zonedDate(item.generatedAt, item.window.timezone)}\n${item.window.timezone} · ${item.sources.length} fuentes',
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push(
                              '/hospitalizations/$id/summaries/${item.id}',
                            ),
                          );
                        },
                      ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: offset == 0 || rows.isLoading
                      ? null
                      : () => setState(() => offset -= 20),
                  child: const Text('Anterior'),
                ),
                TextButton(
                  onPressed:
                      !rows.isLoading &&
                          !rows.hasError &&
                          rows.valueOrNull?.length == 20
                      ? () => setState(() => offset += 20)
                      : null,
                  child: const Text('Siguiente'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class GeneratePeriodSummaryScreen extends ConsumerStatefulWidget {
  const GeneratePeriodSummaryScreen({
    super.key,
    required this.hospitalizationId,
  });
  final String hospitalizationId;
  @override
  ConsumerState<GeneratePeriodSummaryScreen> createState() => _GenerateState();
}

class _GenerateState extends ConsumerState<GeneratePeriodSummaryScreen> {
  DateTime anchor = DateTime.now().toUtc();
  int hours = 24;
  DateTime? customFrom, customTo;
  final kinds = SummarySourceKind.values.toSet();
  bool previewCurrent = false;
  bool navigated = false;

  SummaryWindow? _window(String zone) {
    if (customFrom != null && customTo == null) return null;
    try {
      return customFrom == null
          ? SummaryWindow.utc(
              from: anchor.subtract(Duration(hours: hours)),
              to: anchor,
              timezone: zone,
            )
          : SummaryWindow.localDateTimes(
              from: customFrom!,
              to: customTo!,
              timezone: zone,
            );
    } on PeriodSummaryException {
      return null;
    }
  }

  Future<void> _pick(String zone, {required bool start}) async {
    final localNow = _inZone(DateTime.now(), zone);
    final initial =
        (start ? customFrom : customTo) ??
        (start ? localNow.subtract(Duration(hours: hours)) : localNow);
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: localNow,
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted || time == null) return;
    setState(() {
      final wall = DateTime.utc(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (start) {
        customFrom = wall;
      } else {
        customTo = wall;
      }
      previewCurrent = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.hospitalizationId;
    final episode = ref.watch(periodSummaryContextProvider(id));
    final model = ref.watch(synthesisProviderProvider);
    final controller = ref.watch(periodSummaryControllerProvider(id));
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final saved = controller.saved;
        if (saved != null &&
            controller.phase == PeriodSummaryPhase.saved &&
            !navigated) {
          navigated = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                ref.read(periodSummaryAllowedProvider) &&
                controller.phase == PeriodSummaryPhase.saved) {
              ref.invalidate(periodSummaryHistoryProvider);
              context.go('/hospitalizations/$id/summaries/${saved.id}');
            }
          });
        }
        final pending = controller.phase == PeriodSummaryPhase.saveFailed;
        final locked = controller.busy || pending;
        return Scaffold(
          appBar: clinicalBackAppBar(context, title: 'Generar resumen'),
          body: _EpisodeBody(
            episode: id,
            child: episode.when(
              skipLoadingOnRefresh: false,
              skipError: false,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                child: TextButton(
                  onPressed: () =>
                      ref.invalidate(periodSummaryContextProvider(id)),
                  child: const Text('Reintentar configuración del episodio'),
                ),
              ),
              data: (value) {
                final window = _window(value.timezone);
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('Zona horaria institucional: ${value.timezone}'),
                    const SizedBox(height: 12),
                    Text(
                      'Periodo',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final h in [6, 12, 24, 48, 168])
                          ChoiceChip(
                            label: Text(h == 168 ? '7 días' : '$h horas'),
                            selected: hours == h && customFrom == null,
                            onSelected: locked
                                ? null
                                : (_) => setState(() {
                                    hours = h;
                                    anchor = DateTime.now().toUtc();
                                    customFrom = null;
                                    customTo = null;
                                    previewCurrent = false;
                                  }),
                          ),
                      ],
                    ),
                    TextButton(
                      onPressed: locked
                          ? null
                          : () => _pick(value.timezone, start: true),
                      child: Text(
                        customFrom == null
                            ? 'Rango personalizado'
                            : 'Desde: ${_date(customFrom!)}',
                      ),
                    ),
                    if (customFrom != null)
                      TextButton(
                        onPressed: locked
                            ? null
                            : () => _pick(value.timezone, start: false),
                        child: Text(
                          customTo == null
                              ? 'Seleccionar fecha y hora de término'
                              : 'Hasta: ${_date(customTo!)}',
                        ),
                      ),
                    Text(
                      window == null
                          ? 'Rango inválido: revisa las fechas y horas. No se permiten horas futuras o inexistentes por cambio horario.'
                          : '${_range(window)} (fin excluido)',
                    ),
                    if (customFrom != null)
                      const Text(
                        'En una hora repetida por cambio horario se utiliza su primera ocurrencia.',
                      ),
                    const SizedBox(height: 16),
                    Text(
                      'Fuentes',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final entry in _labels.entries)
                          FilterChip(
                            label: Text(entry.value),
                            selected: kinds.contains(entry.key),
                            onSelected: locked
                                ? null
                                : (selected) => setState(() {
                                    if (selected) {
                                      kinds.add(entry.key);
                                    } else {
                                      kinds.remove(entry.key);
                                    }
                                    previewCurrent = false;
                                  }),
                          ),
                      ],
                    ),
                    const Text(
                      'Los eventos sin hora se incluyen por día, indicando su precisión. Los eventos sin fecha se excluyen.',
                    ),
                    const SizedBox(height: 12),
                    const Text(_historicalWarning),
                    model.when(
                      skipLoadingOnRefresh: false,
                      skipError: false,
                      loading: () => const Text('Preparando modelo local…'),
                      error: (_, __) =>
                          const Text('No se pudo preparar el modelo local.'),
                      data: (provider) => Text(
                        provider?.isAvailable == true
                            ? 'Modelo local disponible.'
                            : 'Modelo local no disponible.',
                      ),
                    ),
                    if (!model.isLoading &&
                        model.valueOrNull?.isAvailable != true)
                      TextButton(
                        onPressed: locked
                            ? null
                            : () => context.push('/models'),
                        child: const Text('Configurar modelo'),
                      ),
                    if (controller.phase == PeriodSummaryPhase.preview &&
                        previewCurrent)
                      Text(
                        'Fuentes incluidas: ${controller.sourceCount}. Sin fecha excluidas: ${controller.excludedUndatedCount}.',
                      ),
                    if (controller.phase == PeriodSummaryPhase.error)
                      Text(
                        _errorMessage(controller.errorCode),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (controller.phase == PeriodSummaryPhase.cancelled)
                      const Text(
                        'Generación cancelada. No se guardó un resumen.',
                      ),
                    if (controller.busy) ...[
                      const Center(child: CircularProgressIndicator()),
                      Text(
                        controller.cancelRequested
                            ? 'Cancelando: el motor puede seguir trabajando hasta finalizar.'
                            : switch (controller.phase) {
                                PeriodSummaryPhase.loadingSources =>
                                  'Consultando fuentes autorizadas…',
                                PeriodSummaryPhase.saving =>
                                  'Guardando resumen…',
                                _ => 'Generando en este dispositivo…',
                              },
                      ),
                    ],
                    if (pending) ...[
                      const Text(
                        'No se pudo confirmar el guardado. Reintenta sin volver a generar el resumen.',
                      ),
                      SelectableText(controller.draft?.prepared.content ?? ''),
                      FilledButton(
                        onPressed: controller.retrySave,
                        child: const Text('Reintentar guardado'),
                      ),
                    ],
                    OutlinedButton(
                      onPressed: locked || kinds.isEmpty || window == null
                          ? null
                          : () async {
                              await controller.preview(window, Set.of(kinds));
                              if (mounted) {
                                setState(
                                  () => previewCurrent =
                                      controller.phase ==
                                      PeriodSummaryPhase.preview,
                                );
                              }
                            },
                      child: const Text('Consultar fuentes'),
                    ),
                    FilledButton(
                      onPressed:
                          locked ||
                              !previewCurrent ||
                              window == null ||
                              model.isLoading ||
                              model.hasError ||
                              model.valueOrNull?.isAvailable != true
                          ? null
                          : () => controller.generate(window, Set.of(kinds)),
                      child: const Text('Generar resumen'),
                    ),
                    if (controller.phase == PeriodSummaryPhase.generating)
                      TextButton(
                        onPressed: controller.cancelRequested
                            ? null
                            : controller.cancelGeneration,
                        child: const Text('Cancelar'),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class PeriodSummaryDetailScreen extends ConsumerWidget {
  const PeriodSummaryDetailScreen({
    super.key,
    required this.hospitalizationId,
    required this.summaryId,
  });
  final String hospitalizationId, summaryId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (episodeId: hospitalizationId, summaryId: summaryId);
    final detail = ref.watch(periodSummaryDetailProvider(key));
    return Scaffold(
      appBar: clinicalBackAppBar(context, title: 'Resumen del periodo'),
      body: _EpisodeBody(
        episode: hospitalizationId,
        child: detail.when(
          skipLoadingOnRefresh: false,
          skipError: false,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
            child: TextButton(
              onPressed: () => ref.invalidate(periodSummaryDetailProvider(key)),
              child: const Text('Resumen no disponible. Reintentar'),
            ),
          ),
          data: (item) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Periodo: ${_range(item.window)}'),
              Text('Zona horaria: ${item.window.timezone}'),
              Text(
                'Generado: ${_zonedDate(item.generatedAt, item.window.timezone)}',
              ),
              const SizedBox(height: 12),
              const Text(_historicalWarning),
              const SizedBox(height: 16),
              SelectableText(item.content),
              const SizedBox(height: 16),
              Text(
                '${item.sources.length} fuentes · ${item.excludedUndatedCount} sin fecha excluidas',
              ),
              ExpansionTile(
                title: const Text('Fuentes incluidas'),
                children: [
                  for (final source in item.sources)
                    ListTile(
                      title: Text(
                        '${_sourceLabel(source.kind)} · ${source.id}',
                      ),
                      subtitle: Text(
                        source.precision == 'date'
                            ? '${source.toJson()['occurred_at']} · sin hora registrada'
                            : '${_zonedDate(source.occurredAt!, item.window.timezone)} · ${item.window.timezone}',
                      ),
                    ),
                ],
              ),
              FilledButton(
                onPressed: () => context.push(
                  '/hospitalizations/$hospitalizationId/summaries/new',
                ),
                child: const Text('Generar otro resumen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _timezonesReady = false;
tz.TZDateTime _inZone(DateTime date, String zone) {
  if (!_timezonesReady) {
    tzdata.initializeTimeZones();
    _timezonesReady = true;
  }
  return tz.TZDateTime.from(date, tz.getLocation(zone));
}

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
String _zonedDate(DateTime date, String zone) => _date(_inZone(date, zone));
String _range(SummaryWindow window) =>
    '${_zonedDate(window.fromUtc, window.timezone)} → ${_zonedDate(window.toUtc, window.timezone)}';
String _sourceLabel(String kind) {
  for (final entry in _labels.entries) {
    if (summaryKindValue(entry.key) == kind) return entry.value;
  }
  return kind;
}

String _errorMessage(String? code) => switch (code) {
  'generation_busy' =>
    'El motor aún está finalizando otro resumen. Espera y vuelve a intentar.',
  'input_over_budget' => 'Hay demasiada información para el modelo local. Reduce el periodo o las categorías; no se omitieron fuentes silenciosamente.',
  'sources_incomplete' =>
    'No se obtuvieron todas las fuentes. Reintenta antes de generar.',
  'no_dated_sources' =>
    'No hay fuentes con fecha para el periodo y filtros seleccionados.',
  'authorization_lost' => 'No fue posible verificar tu acceso al episodio.',
  'invalid_output' =>
    'El modelo devolvió una respuesta no válida. No se guardó el resumen.',
  'provider_unavailable' => 'El modelo local no está disponible.',
  'nonexistent_local_time' ||
  'invalid_window' ||
  'timezone_mismatch' => 'Revisa el rango y la zona horaria institucional.',
  _ => 'No fue posible generar el resumen. Puedes reintentar.',
};
