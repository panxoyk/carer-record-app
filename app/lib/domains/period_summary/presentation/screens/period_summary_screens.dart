import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../../core/design_system/clinical_design_system.dart';
import '../../../patient/presentation/patient_providers.dart';
import '../../domain/period_summary.dart';
import '../controllers/period_summary_controller.dart';
import '../period_summary_providers.dart';

enum _PeriodMode { sixHours, twelveHours, day, dates }

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
    this.clock = DateTime.now,
  });
  final String hospitalizationId;
  final DateTime Function() clock;
  @override
  ConsumerState<GeneratePeriodSummaryScreen> createState() => _GenerateState();
}

class _GenerateState extends ConsumerState<GeneratePeriodSummaryScreen> {
  DateTime? fromDate, throughDate;
  bool _initialized = false;
  _PeriodMode _mode = _PeriodMode.day;
  String? _invalidatedSavedId;
  bool _invalidWindow = false;

  @override
  Widget build(BuildContext context) {
    final id = widget.hospitalizationId;
    final episode = ref.watch(periodSummaryContextProvider(id));
    final controller = ref.watch(periodSummaryControllerProvider(id));
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
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
                final previewNow = widget.clock();
                final now = _inZone(previewNow, value.timezone);
                if (!_initialized) {
                  fromDate = DateTime(now.year, now.month, now.day);
                  throughDate = fromDate;
                  _initialized = true;
                }
                SummaryWindow? window;
                try {
                  window = _mode == _PeriodMode.dates
                      ? SummaryWindow.localDates(
                          fromDate: fromDate!,
                          throughDate: throughDate!,
                          timezone: value.timezone,
                          now: previewNow,
                        )
                      : SummaryWindow.utc(
                          from: previewNow.toUtc().subtract(
                            Duration(hours: _hours(_mode)),
                          ),
                          to: previewNow,
                          timezone: value.timezone,
                          now: previewNow,
                        );
                } on PeriodSummaryException {
                  window = null;
                }
                final saved = controller.saved;
                if (saved != null && _invalidatedSavedId != saved.id) {
                  _invalidatedSavedId = saved.id;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && controller.saved?.id == saved.id) {
                      ref.invalidate(periodSummaryHistoryProvider);
                    }
                  });
                }
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      _windowLabel(
                        controller.resultWindow ?? window,
                        mode: _mode,
                      ),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final entry in const [
                          (_PeriodMode.sixHours, 'Últimas 6 h'),
                          (_PeriodMode.twelveHours, 'Últimas 12 h'),
                          (_PeriodMode.day, 'Últimas 24 h'),
                          (_PeriodMode.dates, 'Elegir fechas'),
                        ])
                          ChoiceChip(
                            label: Text(entry.$2),
                            selected: _mode == entry.$1,
                            onSelected: locked
                                ? null
                                : (_) {
                                    controller.clearResult();
                                    setState(() {
                                      _mode = entry.$1;
                                      _invalidWindow = false;
                                    });
                                  },
                          ),
                      ],
                    ),
                    if (_mode == _PeriodMode.dates)
                      OutlinedButton.icon(
                        onPressed: locked
                            ? null
                            : () async {
                                final picked = await showDateRangePicker(
                                  context: context,
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime(
                                    now.year,
                                    now.month,
                                    now.day,
                                  ),
                                  currentDate: DateTime(
                                    now.year,
                                    now.month,
                                    now.day,
                                  ),
                                  initialDateRange:
                                      fromDate == null || throughDate == null
                                      ? null
                                      : DateTimeRange(
                                          start: fromDate!,
                                          end: throughDate!,
                                        ),
                                );
                                if (!mounted || picked == null) return;
                                controller.clearResult();
                                _invalidWindow = false;
                                setState(() {
                                  fromDate = picked.start;
                                  throughDate = picked.end;
                                });
                              },
                        icon: const Icon(Icons.calendar_month),
                        label: Text(
                          fromDate == null || throughDate == null
                              ? 'Seleccionar fechas'
                              : '${_calendar(fromDate!)} – ${_calendar(throughDate!)}',
                        ),
                      ),
                    if (_mode == _PeriodMode.dates && window == null)
                      const Text('El periodo seleccionado no es válido.'),
                    if (controller.phase == PeriodSummaryPhase.error)
                      Text(
                        _errorMessage(controller.errorCode),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (controller.phase == PeriodSummaryPhase.error &&
                        controller.errorCode == 'provider_unavailable')
                      TextButton(
                        onPressed: () => context.push('/models'),
                        child: const Text('Revisar ajustes de IA'),
                      ),
                    if (_invalidWindow)
                      Text(
                        'El periodo seleccionado no es válido para la hora actual.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (controller.phase == PeriodSummaryPhase.cancelled)
                      const Text(
                        'Generación cancelada. No se guardó un resumen.',
                      ),
                    if (pending) ...[
                      const Text(
                        'Guardado pendiente. Puedes reintentar sin volver a generar.',
                      ),
                      FilledButton(
                        onPressed: controller.retrySave,
                        child: const Text('Reintentar guardado'),
                      ),
                    ],
                    FilledButton(
                      onPressed: locked || window == null
                          ? null
                          : () {
                              try {
                                final generationNow = widget.clock();
                                final generationWindow =
                                    _mode == _PeriodMode.dates
                                    ? SummaryWindow.localDates(
                                        fromDate: fromDate!,
                                        throughDate: throughDate!,
                                        timezone: value.timezone,
                                        now: generationNow,
                                      )
                                    : SummaryWindow.utc(
                                        from: generationNow.toUtc().subtract(
                                          Duration(hours: _hours(_mode)),
                                        ),
                                        to: generationNow,
                                        timezone: value.timezone,
                                        now: generationNow,
                                      );
                                _invalidWindow = false;
                                controller.generate(
                                  generationWindow,
                                  SummarySourceKind.values.toSet(),
                                );
                              } on PeriodSummaryException {
                                setState(() => _invalidWindow = true);
                              }
                            },
                      child: const Text('Generar resumen'),
                    ),
                    _SynthesisCard(
                      text:
                          controller.saved?.content ??
                          controller.draft?.prepared.content,
                      pending: pending,
                      saving: controller.phase == PeriodSummaryPhase.saving,
                      loading:
                          controller.phase == PeriodSummaryPhase.generating ||
                          controller.phase == PeriodSummaryPhase.loadingSources,
                    ),
                    if (controller.phase == PeriodSummaryPhase.generating &&
                        !controller.cancelRequested)
                      TextButton(
                        onPressed: controller.cancelGeneration,
                        child: const Text('Cancelar generación'),
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

class _SynthesisCard extends StatelessWidget {
  const _SynthesisCard({
    required this.text,
    required this.pending,
    required this.saving,
    required this.loading,
  });
  final String? text;
  final bool pending, saving, loading;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 150),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(ClinicalRadii.card),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (text == null || loading) ...[
          Text('Síntesis', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
        ],
        if (saving) ...[const Text('Guardando…'), const SizedBox(height: 8)],
        if (pending) ...[
          const Text('Guardado pendiente'),
          const SizedBox(height: 8),
        ],
        SelectableText(
          loading
              ? 'Redactando síntesis…'
              : (text ?? 'La síntesis aparecerá aquí al generar el resumen.'),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
        ),
      ],
    ),
  );
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
              Text(
                _range(item.window),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              _SynthesisCard(
                text: item.content,
                pending: false,
                saving: false,
                loading: false,
              ),
              const SizedBox(height: 16),
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
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
String _calendar(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
String _range(SummaryWindow window) {
  final start = _inZone(window.fromUtc, window.timezone);
  final end = _inZone(window.toUtc, window.timezone);
  final startAtMidnight =
      start.hour == 0 &&
      start.minute == 0 &&
      start.second == 0 &&
      start.millisecond == 0 &&
      start.microsecond == 0;
  final endAtMidnight =
      end.hour == 0 &&
      end.minute == 0 &&
      end.second == 0 &&
      end.millisecond == 0 &&
      end.microsecond == 0;
  if (endAtMidnight) {
    if (!startAtMidnight) return '${_date(start)} – ${_date(end)}';
    final inclusiveEnd = DateTime.utc(end.year, end.month, end.day - 1);
    return '${_calendar(start)} – ${_calendar(inclusiveEnd)}';
  }
  return '${_date(start)} – ${_date(end)}';
}

int _hours(_PeriodMode mode) => switch (mode) {
  _PeriodMode.sixHours => 6,
  _PeriodMode.twelveHours => 12,
  _ => 24,
};

String _windowLabel(SummaryWindow? window, {required _PeriodMode mode}) {
  if (window == null) {
    return mode == _PeriodMode.dates
        ? 'Periodo seleccionado'
        : switch (mode) {
            _PeriodMode.sixHours => 'Últimas 6 h',
            _PeriodMode.twelveHours => 'Últimas 12 h',
            _ => 'Últimas 24 h',
          };
  }
  if (mode != _PeriodMode.dates) {
    return switch (mode) {
      _PeriodMode.sixHours => 'Últimas 6 h · ${_range(window)}',
      _PeriodMode.twelveHours => 'Últimas 12 h · ${_range(window)}',
      _ => 'Últimas 24 h · ${_range(window)}',
    };
  }
  return _range(window);
}

String _errorMessage(String? code) => switch (code) {
  'input_over_budget' => 'Hay demasiada información para este periodo. Reduce el periodo e intenta nuevamente.',
  'incomplete_output' =>
    'No se completó la síntesis y no se guardó. Puedes intentar nuevamente.',
  'measurement_unavailable' =>
    'No se pudo completar la síntesis. Intenta nuevamente más tarde.',
  'invalid_output' => 'El modelo devolvió los datos de entrada o una respuesta sin síntesis válida. No se guardó el resumen.',
  'provider_unavailable' => 'La síntesis no está disponible en este momento.',
  'generation_busy' =>
    'Espera a que termine el intento anterior y vuelve a intentar.',
  'sources_incomplete' =>
    'No se pudo reunir toda la información del periodo. Intenta nuevamente.',
  'no_dated_sources' =>
    'No hay información fechada en el periodo seleccionado.',
  'authorization_lost' => 'No fue posible verificar tu acceso al episodio.',
  'nonexistent_local_time' || 'invalid_window' || 'timezone_mismatch' =>
    'El periodo seleccionado no es válido para la zona horaria institucional.',
  _ => 'No fue posible generar el resumen. Puedes intentar nuevamente.',
};
