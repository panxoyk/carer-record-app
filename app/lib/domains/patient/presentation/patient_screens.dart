import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/clinical_design_system.dart';
import '../../../core/design_system/clinical_toast.dart';
import '../../../core/time/clinical_time.dart';
import '../../clinical_event/domain/entities/clinical_event.dart';
import '../../clinical_event/presentation/clinical_event_providers.dart';
import '../../context_note/presentation/milestone_editor_sheet.dart';
import '../../institutional/presentation/iam_providers.dart';
import '../../fhir_record/presentation/fhir_record_providers.dart';
import '../../fhir_record/domain/authorized_clinical_record.dart';
import '../../../core/session/authorization_refresh.dart';
import '../domain/entities/patient.dart';
import 'patient_providers.dart';

class PatientsScreen extends ConsumerStatefulWidget {
  const PatientsScreen({super.key});
  @override
  ConsumerState<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends ConsumerState<PatientsScreen> {
  /// El texto vive en el State y no en el campo: una recarga del censo
  /// remonta la lista, y el campo debe conservar lo escrito y el foco.
  final _searchController = TextEditingController();
  String query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(patientsProvider);
    final iamContext = ref.watch(iamContextProvider);
    return Scaffold(
      bottomNavigationBar: const ClinicalBottomNavigation(selectedIndex: 0),
      appBar: clinicalAppBar(title: 'Hospitalizaciones'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => query = value),
              decoration: clinicalInputDecoration(
                labelText: 'Buscar por nombre',
              ),
            ),
          ),

          ///          Padding(
          ///            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          ///            child: Align(
          ///              alignment: Alignment.centerLeft,
          ///              child: OutlinedButton.icon(
          ///                onPressed: () => context.push('/fhir/patients'),
          ///                icon: const Icon(Icons.search),
          ///                label: const Text('Buscar ficha clínica (HAPI FHIR)'),
          ///              ),
          ///            ),
          ///          ),
          Expanded(
            child: result.when(
              skipLoadingOnRefresh: false,
              skipError: false,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(child: _RetryPatients(onRetry: _retry)),
              data: (items) {
                final visible = items
                    .where((item) => item.matchesSearch(query))
                    .toList();
                if (visible.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () =>
                        ref.refresh(patientsProvider.future).then<void>((_) {}),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: 160,
                          child: Center(
                            child: Text(
                              items.isEmpty
                                  ? 'No hay pacientes disponibles para tu acceso.'
                                  : 'No se encontraron pacientes con este nombre.',
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () =>
                      ref.refresh(patientsProvider.future).then<void>((_) {}),
                  child: ListView(
                    children: [
                      for (final item in visible)
                        ListTile(
                          title: Text(item.fullName),
                          subtitle: Text(
                            '${item.hospitalizationStatus == 'discharged'
                                ? 'Cerrada'
                                : item.hospitalizationStatus == 'temporarily_absent'
                                ? 'Ausente temporalmente'
                                : 'Abierta'} · ${item.locationLabel}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            final canReadTimeline =
                                iamContext.valueOrNull?.allows(
                                  'clinical.timeline.read',
                                ) ??
                                false;
                            context.push(
                              canReadTimeline
                                  ? '/hospitalizations/${item.hospitalizationId}'
                                  : '/hospitalizations/${item.hospitalizationId}/details',
                            );
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _retry() => ref.invalidate(patientsProvider);
}

class _RetryPatients extends StatelessWidget {
  const _RetryPatients({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('No fue posible cargar las hospitalizaciones.'),
        const SizedBox(height: ClinicalSpacing.item),
        FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
      ],
    ),
  );
}

class PatientDetailScreen extends ConsumerWidget {
  const PatientDetailScreen({required this.hospitalizationId, super.key});
  final String hospitalizationId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patient = ref.watch(patientProvider(hospitalizationId));
    final fhir = ref.watch(
      authorizedClinicalTimelineProvider(hospitalizationId),
    );
    final iamState = ref.watch(iamContextProvider);
    final iam = iamState.valueOrNull;
    // UI guard only: RLS on context_notes remains the authorization authority.
    final canAddMilestone =
        patient.hasValue &&
        !patient.isLoading &&
        !patient.hasError &&
        !iamState.isLoading &&
        !iamState.hasError &&
        fhir.valueOrNull?.hospitalization.status != 'discharged' &&
        (patient.valueOrNull?.hospitalizationStatus == 'admitted' ||
            patient.valueOrNull?.hospitalizationStatus ==
                'temporarily_absent') &&
        (iam?.allows('context.note.create') ?? false) &&
        (iam?.allows('context.note.confirm') ?? false);
    if (fhir.hasValue && fhir.valueOrNull == null) {
      return Scaffold(
        appBar: clinicalBackAppBar(context, title: 'Bitácora'),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'No se pudo verificar el acceso. Vuelve a cargar la pantalla.',
              ),
              const SizedBox(height: ClinicalSpacing.item),
              FilledButton(
                onPressed: () {
                  ref.invalidate(
                    authorizedClinicalTimelineProvider(hospitalizationId),
                  );
                  ref.invalidate(patientProvider(hospitalizationId));
                },
                child: const Text('Reintentar autorización'),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: clinicalBackAppBar(
        context,
        title: 'Bitácora',
        actions: canAddMilestone && patient.valueOrNull != null
            ? [
                IconButton(
                  tooltip: 'Añadir nota de contexto',
                  icon: const Icon(Icons.add_task_outlined),
                  onPressed: () {
                    final item = patient.valueOrNull;
                    if (item == null) return;
                    showMilestoneEditorSheet(
                      context,
                      patient: item,
                      onSaved: (cleanupPending) {
                        if (!context.mounted) return;
                        ref.invalidate(
                          hospitalizationClinicalEventsProvider(
                            hospitalizationId,
                          ),
                        );
                        ClinicalToast.success(
                          context,
                          message: cleanupPending
                              ? 'Nota guardada. La limpieza local quedó pendiente.'
                              : 'Nota guardada.',
                          withDetails: cleanupPending,
                        );
                      },
                    );
                  },
                ),
              ]
            : null,
      ),
      body: patient.when(
        skipLoadingOnRefresh: false,
        skipError: false,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: FilledButton(
            onPressed: () => ref.invalidate(patientProvider(hospitalizationId)),
            child: const Text('Reintentar carga de hospitalización'),
          ),
        ),
        data: (item) => item == null
            ? const Center(child: Text('Paciente no encontrado.'))
            : _HospitalizationTimeline(patient: item),
      ),
    );
  }
}

class _HospitalizationTimeline extends ConsumerWidget {
  const _HospitalizationTimeline({required this.patient});
  final Patient patient;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(
      hospitalizationClinicalEventsProvider(patient.hospitalizationId),
    );
    final fhir = ref.watch(
      authorizedClinicalTimelineProvider(patient.hospitalizationId),
    );
    return RefreshIndicator(
      onRefresh: () async {
        ref.read(authorizationRefreshProvider)();
        await Future.wait([
          ref.refresh(patientProvider(patient.hospitalizationId).future),
          ref.refresh(
            hospitalizationClinicalEventsProvider(patient.hospitalizationId)
                .future,
          ),
          ref.refresh(
            authorizedClinicalTimelineProvider(patient.hospitalizationId)
                .future,
          ),
        ]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (fhir.hasError)
            _IncompleteWarning(
              'FHIR no disponible. Se muestran solo las notas autorizadas.',
              onRetry: () => ref.invalidate(
                authorizedClinicalTimelineProvider(patient.hospitalizationId),
              ),
            ),
          if (events.hasError)
            const _IncompleteWarning(
              'No fue posible cargar las notas de contexto.',
            ),
          if (!fhir.hasError && !fhir.isLoading && fhir.valueOrNull != null)
            _TimelineHeader(patient: patient, record: fhir.value!),
          if (fhir.hasError) _TimelineHeader(patient: patient),
          if (fhir.isLoading || events.isLoading)
            const Padding(
              padding: EdgeInsets.all(ClinicalSpacing.card),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (!fhir.isLoading && !events.isLoading)
            _TimelineGroups(
              fhirItems: fhir.hasError
                  ? const []
                  : fhir.valueOrNull?.timeline ?? const [],
              events: events.hasError
                  ? const []
                  : events.valueOrNull ?? const [],
            ),
        ],
      ),
    );
  }
}

class _TimelineHeader extends StatelessWidget {
  const _TimelineHeader({required this.patient, this.record});
  final Patient patient;
  final AuthorizedClinicalRecord? record;

  @override
  Widget build(BuildContext context) {
    final fhirPatient = record?.patient;
    final birth = fhirPatient?.birthDate;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ClinicalSpacing.page,
        ClinicalSpacing.item,
        ClinicalSpacing.page,
        ClinicalSpacing.item,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClinicalCard(
            padding: const EdgeInsets.all(ClinicalSpacing.card),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patient.fullName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (fhirPatient?.identifier != null)
                  Text('Identificador: ${fhirPatient!.identifier}'),
                if (birth != null)
                  Text(
                    'Nacimiento: ${_dateOnly(birth)}${_ageAt(birth) == null ? '' : ' · ${_ageAt(birth)} años'}',
                  ),
                if (birth == null && patient.birthDate != null)
                  Text('Nacimiento: ${formatClinicalDate(patient.birthDate)}'),
                const Divider(),
                Text(
                  '${patient.hospitalizationStatus == 'discharged'
                      ? 'Cerrada'
                      : patient.hospitalizationStatus == 'temporarily_absent'
                      ? 'Ausente temporalmente'
                      : patient.hospitalizationStatus == 'planned'
                      ? 'Planificada'
                      : 'Abierta'} · ${patient.locationLabel}',
                ),
                if (patient.hospitalizationStatus == 'discharged')
                  Text(
                    'Egreso: ${patient.dischargedAt == null ? 'sin fecha registrada' : formatClinicalDate(patient.dischargedAt)}',
                  ),
                if (patient.hospitalizationStatus == 'discharged')
                  const Text('Solo lectura'),
              ],
            ),
          ),
          const SizedBox(height: ClinicalSpacing.compact),
          ClinicalCard(
            child: ListTile(
              leading: const Icon(Icons.medical_information_outlined),
              title: const Text('Ver ficha clínica electrónica'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(
                '/hospitalizations/${patient.hospitalizationId}/record',
              ),
            ),
          ),
          if (record?.truncated == true || record?.status == 'partial')
            const _IncompleteWarning(
              'Bitácora incompleta: la fuente FHIR devolvió información parcial.',
            ),
          const Padding(
            padding: EdgeInsets.only(top: ClinicalSpacing.section),
            child: ClinicalSectionTitle('Bitácora'),
          ),
        ],
      ),
    );
  }
}

class _TimelineGroups extends StatelessWidget {
  const _TimelineGroups({required this.fhirItems, required this.events});
  final List<ClinicalTimelineItem> fhirItems;
  final List<ClinicalEvent> events;

  @override
  Widget build(BuildContext context) {
    final dated = <({DateTime time, String id, Widget child})>[];
    final dateOnlyRows = <({String date, String id, Widget child})>[];
    final undated = <({String id, Widget child})>[];
    final seen = <String>{};
    for (final item in fhirItems) {
      final key = 'FHIR:${item.id}';
      if (!seen.add(key)) continue;
      final hasDateOnlyPrecision = item.precision == 'date';
      final widget = _TimelineCard(
        title: item.title,
        source: 'FHIR',
        date: item.occurredAt,
        detail: item.detail,
        dateOnly: hasDateOnlyPrecision,
      );
      if (item.occurredAt == null) {
        undated.add((id: key, child: widget));
      } else if (hasDateOnlyPrecision) {
        dateOnlyRows.add((date: item.occurredAt!, id: key, child: widget));
      } else {
        final parsed = DateTime.tryParse(item.occurredAt!);
        if (parsed != null) dated.add((time: parsed, id: key, child: widget));
      }
    }
    for (final event in events) {
      final key = '${event.sourceKind}:${event.id}';
      if (!seen.add(key)) continue;
      dated.add((
        time: event.occurredAt,
        id: key,
        child: _TimelineCard(
          title: event.summary,
          source: event.isMilestone ? 'Nota de contexto' : 'Evento clínico',
          date: event.occurredAt.toIso8601String(),
          dateOnly: false,
          detail: event.isDictatedMilestone ? 'Dictado local' : null,
        ),
      ));
    }
    dated.sort((a, b) {
      final byTime = b.time.compareTo(a.time);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    dateOnlyRows.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    undated.sort((a, b) => a.id.compareTo(b.id));
    if (dated.isEmpty && dateOnlyRows.isEmpty && undated.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(ClinicalSpacing.page),
        child: Text('No hay eventos disponibles.'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (dated.isNotEmpty)
          for (final row in dated) row.child,
        if (dateOnlyRows.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(
              ClinicalSpacing.page,
              ClinicalSpacing.section,
              ClinicalSpacing.page,
              ClinicalSpacing.compact,
            ),
            child: ClinicalSectionTitle('Eventos con fecha sin hora'),
          ),
          for (final row in dateOnlyRows) row.child,
        ],
        if (undated.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(
              ClinicalSpacing.page,
              ClinicalSpacing.section,
              ClinicalSpacing.page,
              ClinicalSpacing.compact,
            ),
            child: ClinicalSectionTitle('Sin fecha'),
          ),
          for (final row in undated) row.child,
        ],
      ],
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.title,
    required this.source,
    required this.date,
    required this.dateOnly,
    this.detail,
  });
  final String title, source;
  final String? date, detail;
  final bool dateOnly;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      ClinicalSpacing.page,
      0,
      ClinicalSpacing.page,
      ClinicalSpacing.compact,
    ),
    child: ClinicalCard(
      padding: const EdgeInsets.all(ClinicalSpacing.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 4),
          Text(
            [
              source,
              if (detail?.isNotEmpty == true) detail!,
              if (date != null)
                '${dateOnly ? 'Solo fecha · ' : ''}${dateOnly ? _dateOnly(date!) : formatClinicalDateTime(DateTime.parse(date!))}',
            ].join(' · '),
          ),
        ],
      ),
    ),
  );
}

class _IncompleteWarning extends StatelessWidget {
  const _IncompleteWarning(this.message, {this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: ClinicalSpacing.page,
      vertical: ClinicalSpacing.compact,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: const TextStyle(color: ClinicalColors.attention)),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Reintentar FHIR')),
      ],
    ),
  );
}

String _dateOnly(String raw) => raw.split('-').reversed.join('-');
int? _ageAt(String raw) {
  final parts = raw.split('-').map(int.tryParse).toList();
  if (parts.length != 3 || parts.any((part) => part == null)) return null;
  final birth = DateTime(parts[0]!, parts[1]!, parts[2]!);
  final now = DateTime.now();
  return now.year -
      birth.year -
      ((now.month < birth.month ||
              (now.month == birth.month && now.day < birth.day))
          ? 1
          : 0);
}

class PatientInformationScreen extends ConsumerWidget {
  const PatientInformationScreen({required this.hospitalizationId, super.key});
  final String hospitalizationId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patient = ref.watch(patientProvider(hospitalizationId));
    return Scaffold(
      appBar: clinicalBackAppBar(context, title: 'Información del paciente'),
      body: patient.when(
        skipLoadingOnRefresh: false,
        skipError: false,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            const Center(child: Text('No fue posible cargar la información.')),
        data: (item) => item == null
            ? const Center(child: Text('Paciente no encontrado.'))
            : RefreshIndicator(
                onRefresh: () => ref
                    .refresh(patientProvider(hospitalizationId).future)
                    .then<void>((_) {}),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    ListTile(
                      title: Text(item.fullName),
                      subtitle: Text(item.locationLabel),
                    ),
                    ListTile(
                      title: const Text('Nacimiento'),
                      subtitle: Text(formatClinicalDate(item.birthDate)),
                    ),
                    ListTile(
                      title: const Text('Hospitalización'),
                      subtitle: Text(
                        '${item.hospitalizationStatus == 'discharged'
                            ? 'Cerrada'
                            : item.hospitalizationStatus == 'temporarily_absent'
                            ? 'Ausente temporalmente'
                            : 'Abierta'} · ${item.locationLabel}',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => context.push(
                        '/hospitalizations/${item.hospitalizationId}/record',
                      ),
                      icon: const Icon(Icons.medical_information_outlined),
                      label: const Text('Ver ficha clínica electrónica'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
