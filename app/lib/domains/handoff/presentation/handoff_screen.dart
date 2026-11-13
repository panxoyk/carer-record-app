import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/clinical/clinical_vocabulary.dart';
import '../../../core/design_system/clinical_design_system.dart';
import '../../../core/design_system/clinical_toast.dart';
import '../../../core/time/clinical_time.dart';
import '../../clinical_event/domain/entities/clinical_event.dart';
import '../../clinical_event/presentation/clinical_event_providers.dart';
import '../../fhir_record/domain/authorized_clinical_record.dart';
import '../../fhir_record/presentation/fhir_record_providers.dart';
import '../../patient/domain/entities/patient.dart';
import '../../patient/presentation/patient_providers.dart';
import '../../period_summary/presentation/period_summary_providers.dart';
import '../../../core/navigation/current_hospitalization.dart';

/// Entrega de turno del diseño Figma: estado actual, cambios recientes y
/// pendientes del episodio, listo para copiar. Usa solo datos que el usuario
/// ya puede leer en la bitácora; no depende de los resúmenes con IA.
class HandoffScreen extends ConsumerStatefulWidget {
  const HandoffScreen({required this.hospitalizationId, super.key});
  final String hospitalizationId;

  @override
  ConsumerState<HandoffScreen> createState() => _HandoffScreenState();
}

class _HandoffScreenState extends ConsumerState<HandoffScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      ref.read(currentHospitalizationProvider.notifier).state =
          widget.hospitalizationId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.hospitalizationId;
    final patient = ref.watch(patientProvider(id));
    final record = ref.watch(authorizedClinicalTimelineProvider(id));
    final events = ref.watch(hospitalizationClinicalEventsProvider(id));
    final summariesAllowed = ref.watch(periodSummaryAllowedProvider);
    final loading = patient.isLoading || record.isLoading || events.isLoading;
    return Scaffold(
      extendBody: true,
      appBar: clinicalBackAppBar(context, title: ''),
      bottomNavigationBar: const ClinicalBottomNavigation(
        current: ClinicalTab.handoff,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : patient.valueOrNull == null
          ? const Center(child: Text('Paciente no encontrado.'))
          : _HandoffBody(
              patient: patient.value!,
              record: record.valueOrNull,
              events: events.valueOrNull ?? const [],
              summariesAllowed: summariesAllowed,
            ),
    );
  }
}

class _HandoffBody extends StatelessWidget {
  const _HandoffBody({
    required this.patient,
    required this.record,
    required this.events,
    required this.summariesAllowed,
  });
  final Patient patient;
  final AuthorizedClinicalRecord? record;
  final List<ClinicalEvent> events;
  final bool summariesAllowed;

  @override
  Widget build(BuildContext context) {
    final handoff = HandoffSummary.build(
      patient: patient,
      record: record,
      events: events,
      now: DateTime.now(),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      children: [
        const ClinicalLargeTitle(
          'Entrega de turno',
          padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
        ),
        ClinicalCard(
          radius: ClinicalRadii.button,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(handoff.context, style: ClinicalTextStyles.headline),
              const SizedBox(height: 4),
              Text(
                'Borrador para revisión · Turno ${handoff.shift}',
                style: ClinicalTextStyles.footnote,
              ),
            ],
          ),
        ),
        for (final section in handoff.sections) ...[
          const SizedBox(height: 12),
          ClinicalCard(
            radius: ClinicalRadii.button,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(section.title, style: ClinicalTextStyles.headline),
                const SizedBox(height: 8),
                for (final line in section.lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      line,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: ClinicalColors.secondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: handoff.asText()));
            if (context.mounted) {
              ClinicalToast.success(context, message: 'Resumen copiado.');
            }
          },
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copiar resumen'),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () =>
              context.push('/hospitalizations/${patient.hospitalizationId}'),
          child: const Text('Ver bitácora'),
        ),
        if (summariesAllowed)
          TextButton.icon(
            onPressed: () => context.push(
              '/hospitalizations/${patient.hospitalizationId}/summaries',
            ),
            icon: const Icon(Icons.auto_awesome_outlined, size: 18),
            label: const Text('Resúmenes con IA'),
          ),
        const SizedBox(height: 8),
        const Text(
          'Este borrador debe ser revisado antes de incorporarse a la ficha clínica oficial.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: ClinicalColors.tertiary),
        ),
      ],
    );
  }
}

class HandoffSection {
  const HandoffSection(this.title, this.lines);
  final String title;
  final List<String> lines;
}

/// Contenido de la entrega, construido solo con datos ya autorizados.
class HandoffSummary {
  const HandoffSummary({
    required this.context,
    required this.shift,
    required this.sections,
  });

  final String context;
  final String shift;
  final List<HandoffSection> sections;

  factory HandoffSummary.build({
    required Patient patient,
    required AuthorizedClinicalRecord? record,
    required List<ClinicalEvent> events,
    required DateTime now,
  }) {
    final unit = patient.unitDisplayName ?? record?.hospitalization.unit;
    final context = [
      patient.fullName,
      ?unit,
      patient.locationLabel,
    ].join(' · ');
    final episode = record?.hospitalization;
    final status = switch (patient.hospitalizationStatus) {
      'admitted' => 'Hospitalización activa',
      'temporarily_absent' => 'Ausencia temporal',
      'discharged' => 'Episodio cerrado',
      _ => 'Estado no confirmado',
    };
    final abnormal = record
        ?.entriesOf(ClinicalSectionType.observations)
        .where((entry) => entry.isAbnormal)
        .toList();
    final current = [
      status,
      if (episode?.reason != null) 'Motivo: ${episode!.reason}',
      if (episode?.attendingPhysician != null)
        'Médico tratante: ${episode!.attendingPhysician}',
      if (abnormal != null && abnormal.isNotEmpty)
        'Valores alterados: ${abnormal.take(3).map((e) => '${e.title} ${e.value ?? ''}'.trim()).join(', ')}',
    ];
    final recent = <({DateTime time, String line})>[
      for (final event in events)
        (
          time: event.occurredAt,
          line:
              '${formatClinicalTime(event.occurredAt)} · ${event.isMilestone ? EventCategory.fromWire(event.category)?.label ?? 'Nota' : 'Registro'}: ${event.summary}',
        ),
      for (final item in record?.timeline ?? const <ClinicalTimelineItem>[])
        if (item.occurredAt != null && item.precision == 'instant')
          (
            time: DateTime.parse(item.occurredAt!),
            line:
                '${formatClinicalTime(DateTime.parse(item.occurredAt!))} · ${item.title}${item.detail == null ? '' : ': ${item.detail}'}',
          ),
    ]..sort((a, b) => b.time.compareTo(a.time));
    final pendingDoses =
        (record?.entriesOf(ClinicalSectionType.administrations) ??
                const <ClinicalRecordEntry>[])
            .where((dose) => dose.administeredAt == null && dose.date != null)
            .map(
              (dose) =>
                  'Dosis sin registro de administración: ${dose.title} · ${formatClinicalDateTime(DateTime.parse(dose.date!))}',
            );
    final pending = [
      ...pendingDoses,
      if (record != null &&
          record.entriesOf(ClinicalSectionType.reports).isEmpty)
        'Sin resultados de exámenes recibidos.',
    ];
    return HandoffSummary(
      context: context,
      shift: clinicalShiftLabel(now),
      sections: [
        HandoffSection('Estado actual', current),
        HandoffSection(
          'Cambios recientes',
          recent.isEmpty
              ? const ['Sin eventos registrados.']
              : recent.take(4).map((row) => row.line).toList(),
        ),
        HandoffSection(
          'Pendientes',
          pending.isEmpty ? const ['Sin pendientes documentados.'] : pending,
        ),
      ],
    );
  }

  String asText() => [
    'Entrega de turno · $shift',
    context,
    for (final section in sections) ...[
      '',
      section.title,
      for (final line in section.lines) '- $line',
    ],
  ].join('\n');
}
