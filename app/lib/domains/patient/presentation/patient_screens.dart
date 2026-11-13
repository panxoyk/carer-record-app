import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/clinical_design_system.dart';
import '../../../core/design_system/clinical_toast.dart';
import '../../../core/navigation/current_hospitalization.dart';
import '../../../core/time/clinical_time.dart';
import '../../clinical_event/domain/entities/clinical_event.dart';
import '../../clinical_event/presentation/clinical_event_providers.dart';
import '../../context_note/presentation/milestone_editor_sheet.dart';
import '../../period_summary/presentation/period_summary_providers.dart';
import '../../institutional/presentation/iam_providers.dart';
import '../../fhir_record/presentation/fhir_record_providers.dart';
import '../../fhir_record/domain/authorized_clinical_record.dart';
import '../../../core/session/authorization_refresh.dart';
import '../domain/entities/patient.dart';
import 'patient_providers.dart';
import '../../../core/clinical/clinical_vocabulary.dart';
import 'widgets/bitacora_cards.dart';
import 'widgets/patient_census_card.dart';
import 'widgets/timeline_entry_card.dart';

/// Servicio (unidad) de un episodio, o null si el censo no lo informa.
String? _serviceOf(Patient patient) {
  final name = patient.unitDisplayName?.trim();
  return name == null || name.isEmpty ? null : name;
}

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

  /// Servicio seleccionado en las píldoras; null muestra todos.
  String? _service;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(patientsProvider);
    final iamContext = ref.watch(iamContextProvider);
    final displayName = iamContext.valueOrNull?.displayName;
    final services = {
      for (final patient in result.valueOrNull ?? const <Patient>[])
        ?_serviceOf(patient),
    }.toList()..sort();
    final service = services.contains(_service) ? _service : null;
    // Toda la pantalla desplaza como una sola lista: con texto grande la
    // cabecera no deja sin espacio a las tarjetas.
    final header = <Widget>[
      _CensusGreeting(displayName: displayName),
      const ClinicalLargeTitle('Casos activos'),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ClinicalSearchField(
          controller: _searchController,
          hintText: 'Buscar paciente...',
          onChanged: (value) => setState(() => query = value),
        ),
      ),
      if (services.isNotEmpty)
        Semantics(
          container: true,
          label: 'Servicios',
          child: ClinicalPillRow(
            children: [
              ClinicalFilterPill(
                label: 'Todos',
                selected: service == null,
                onTap: () => setState(() => _service = null),
              ),
              for (final name in services)
                ClinicalFilterPill(
                  label: name,
                  selected: service == name,
                  onTap: () => setState(() => _service = name),
                ),
            ],
          ),
        ),
      const SizedBox(height: 16),
    ];
    final List<Widget> content = result.when(
      skipLoadingOnRefresh: false,
      skipError: false,
      loading: () => const [
        Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
      error: (_, __) => [
        Padding(
          padding: const EdgeInsets.all(32),
          child: _RetryPatients(onRetry: _retry),
        ),
      ],
      data: (items) {
        final visible = items
            .where((item) => item.matchesSearch(query))
            .where((item) => service == null || _serviceOf(item) == service)
            .toList();
        return [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service == null
                      ? 'Pacientes a tu cargo'
                      : 'Pacientes del servicio $service',
                  style: ClinicalTextStyles.sectionTitle,
                ),
                Text(
                  '${visible.length} ${visible.length == 1 ? 'caso' : 'casos'}'
                      .toUpperCase(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .5,
                    color: ClinicalColors.secondary,
                  ),
                ),
              ],
            ),
          ),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Text(
                items.isEmpty
                    ? 'No hay pacientes disponibles para tu acceso.'
                    : query.trim().isEmpty
                    ? 'No hay pacientes en este filtro.'
                    : 'No se encontraron pacientes con este nombre.',
                style: const TextStyle(
                  fontSize: 15,
                  color: ClinicalColors.secondary,
                ),
              ),
            ),
          for (final item in visible)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: PatientCensusCard(
                patient: item,
                service: _serviceOf(item),
                serviceTint: serviceTint(
                  services.indexOf(_serviceOf(item) ?? ''),
                ),
                status: _hospitalizationStatusBadge(item.hospitalizationStatus),
                location: _patientLocationLabel(item),
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
            ),
        ];
      },
    );
    return Scaffold(
      extendBody: true,
      bottomNavigationBar: const ClinicalBottomNavigation(
        current: ClinicalTab.cases,
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () =>
              ref.refresh(patientsProvider.future).then<void>((_) {}),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 120),
            children: [...header, ...content],
          ),
        ),
      ),
    );
  }

  void _retry() => ref.invalidate(patientsProvider);
}

/// Saludo, fecha y avatar del profesional en la cabecera del censo.
class _CensusGreeting extends StatelessWidget {
  const _CensusGreeting({required this.displayName});
  final String? displayName;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Buenos días,'
        : now.hour < 20
        ? 'Buenas tardes,'
        : 'Buenas noches,';
    final name = displayName?.trim();
    final hasName = name != null && name.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: const TextStyle(
                    fontSize: 16,
                    color: ClinicalColors.secondary,
                  ),
                ),
                if (hasName)
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 26,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: ClinicalColors.ink,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  _spanishLongDate(now),
                  style: const TextStyle(
                    fontSize: 13,
                    color: ClinicalColors.tertiary,
                  ),
                ),
              ],
            ),
          ),
          if (hasName) ...[
            const SizedBox(width: 12),
            Tooltip(
              message: 'Ajustes',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => context.go('/settings'),
                child: ClinicalAvatar(
                  initials: clinicalInitials(name),
                  size: 38,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _spanishLongDate(DateTime date) {
  const days = [
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
    'domingo',
  ];
  const months = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];
  return '${days[date.weekday - 1]}, ${date.day} de ${months[date.month - 1]}';
}

Widget _hospitalizationStatusBadge(String status) => switch (status) {
  'admitted' => Semantics(
    label: 'Hospitalización activa',
    child: const ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 7,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: ClinicalColors.mintDark,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    ),
  ),
  'discharged' => const ClinicalBadge(
    label: 'Solo lectura',
    color: ClinicalColors.fillSubtle,
    textColor: ClinicalColors.secondary,
    icon: Icons.lock_outline,
  ),
  'temporarily_absent' => const ClinicalBadge(
    label: 'Ausencia temporal',
    color: ClinicalColors.softAttention,
    textColor: ClinicalColors.attention,
  ),
  'planned' => const ClinicalBadge(
    label: 'Planificada',
    color: ClinicalColors.softObservation,
    textColor: ClinicalColors.observationText,
  ),
  'cancelled' => const ClinicalBadge(
    label: 'Cancelada',
    color: ClinicalColors.softObservation,
    textColor: ClinicalColors.observationText,
  ),
  _ => const ClinicalBadge(
    label: 'Estado no confirmado',
    color: ClinicalColors.softObservation,
    textColor: ClinicalColors.observationText,
  ),
};

String _patientLocationLabel(Patient patient) {
  final bed = patient.bedLabel?.trim();
  if (bed == null || bed.isEmpty) return patient.locationLabel;
  return RegExp(r'^Cama\s+', caseSensitive: false).hasMatch(bed)
      ? bed
      : 'Cama $bed';
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

class PatientDetailScreen extends ConsumerStatefulWidget {
  const PatientDetailScreen({required this.hospitalizationId, super.key});
  final String hospitalizationId;

  @override
  ConsumerState<PatientDetailScreen> createState() =>
      _PatientDetailScreenState();
}

class _PatientDetailScreenState extends ConsumerState<PatientDetailScreen> {
  String get hospitalizationId => widget.hospitalizationId;

  @override
  void initState() {
    super.initState();
    // La barra inferior recuerda el último episodio abierto (solo navegación).
    Future.microtask(() {
      if (!mounted) return;
      ref.read(currentHospitalizationProvider.notifier).state =
          hospitalizationId;
    });
  }

  void _openEditor(Patient item) {
    showMilestoneEditorSheet(
      context,
      patient: item,
      onSaved: (cleanupPending) {
        if (!mounted) return;
        ref.invalidate(
          hospitalizationClinicalEventsProvider(hospitalizationId),
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
  }

  @override
  Widget build(BuildContext context) {
    final patient = ref.watch(patientProvider(hospitalizationId));
    final fhir = ref.watch(
      authorizedClinicalTimelineProvider(hospitalizationId),
    );
    final iamState = ref.watch(iamContextProvider);
    final summaryAllowed = ref.watch(periodSummaryAllowedProvider);
    final iam = iamState.valueOrNull;
    // UI guard only: RLS on context_notes remains the authorization authority.
    final canAddMilestone =
        patient.hasValue &&
        !patient.isLoading &&
        !patient.hasError &&
        !iamState.isLoading &&
        !iamState.hasError &&
        fhir.valueOrNull?.hospitalization.status != 'discharged' &&
        patient.valueOrNull?.hospitalizationStatus != 'discharged' &&
        (patient.valueOrNull?.hospitalizationStatus == 'admitted' ||
            patient.valueOrNull?.hospitalizationStatus ==
                'temporarily_absent') &&
        (iam?.allows('context.note.create') ?? false) &&
        (iam?.allows('context.note.confirm') ?? false);
    final showSummaries =
        summaryAllowed &&
        patient.hasValue &&
        !patient.isLoading &&
        !patient.hasError &&
        patient.valueOrNull != null &&
        !iamState.isLoading &&
        !iamState.hasError;
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
    final item = patient.valueOrNull;
    final openEditor = canAddMilestone && item != null
        ? () => _openEditor(item)
        : null;
    return Scaffold(
      extendBody: true,
      appBar: clinicalBackAppBar(
        context,
        title: '',
        actions: [
          if (openEditor != null)
            ClinicalRoundIconButton(
              tooltip: 'Añadir nota de contexto',
              icon: Icons.add_rounded,
              onPressed: openEditor,
            ),
        ],
      ),
      bottomNavigationBar: ClinicalBottomNavigation(
        current: ClinicalTab.timeline,
        onRecord: openEditor,
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
            : _HospitalizationTimeline(
                patient: item,
                showSummaries: showSummaries,
              ),
      ),
    );
  }
}

class _HospitalizationTimeline extends ConsumerWidget {
  const _HospitalizationTimeline({
    required this.patient,
    required this.showSummaries,
  });
  final Patient patient;
  final bool showSummaries;
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
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ClinicalLargeTitle('Bitácora'),
            _PatientSwitcher(
              currentHospitalizationId: patient.hospitalizationId,
            ),
            if (fhir.hasError)
              _IncompleteWarning(
                'No fue posible cargar la ficha clínica. Se muestran solo las notas disponibles.',
                onRetry: () => ref.invalidate(
                  authorizedClinicalTimelineProvider(patient.hospitalizationId),
                ),
              ),
            if (events.hasError)
              const _IncompleteWarning(
                'No fue posible cargar la bitácora. Vuelve a intentarlo.',
              ),
            if (!fhir.hasError && !fhir.isLoading && fhir.valueOrNull != null)
              _TimelineHeader(
                patient: patient,
                record: fhir.value!,
                showSummaries: showSummaries,
              ),
            if (fhir.hasError)
              _TimelineHeader(patient: patient, showSummaries: showSummaries),
            if (fhir.valueOrNull != null) ...[
              VitalSignsCard(record: fhir.value!),
              BloodResultsCard(record: fhir.value!),
            ],
            if (fhir.isLoading || events.isLoading)
              const Padding(
                padding: EdgeInsets.all(ClinicalSpacing.card),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!fhir.isLoading && !events.isLoading)
              _TimelineGroups(
                hospitalizationId: patient.hospitalizationId,
                record: fhir.hasError ? null : fhir.valueOrNull,
                fhirItems: fhir.hasError
                    ? const []
                    : fhir.valueOrNull?.timeline ?? const [],
                events: events.hasError
                    ? const []
                    : events.valueOrNull ?? const [],
              ),
          ],
        ),
      ),
    );
  }
}

/// Selector de pacientes en píldoras (estilo pestañas de Safari) a partir del
/// censo ya autorizado. Se oculta si el censo no está disponible.
class _PatientSwitcher extends ConsumerWidget {
  const _PatientSwitcher({required this.currentHospitalizationId});
  final String currentHospitalizationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final census = ref.watch(patientsProvider).valueOrNull ?? const <Patient>[];
    if (census.length < 2 ||
        !census.any((p) => p.hospitalizationId == currentHospitalizationId)) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.only(bottom: 12),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: ClinicalColors.separator)),
      ),
      child: ClinicalPillRow(
        children: [
          for (final p in census)
            ClinicalFilterPill(
              label: p.familyName,
              trailing: p.bedLabel?.trim().isNotEmpty == true
                  ? p.bedLabel!.replaceFirst(
                      RegExp(r'^Cama\s+', caseSensitive: false),
                      '',
                    )
                  : null,
              leadingDot: ClinicalColors.mint,
              selected: p.hospitalizationId == currentHospitalizationId,
              onTap: () {
                if (p.hospitalizationId == currentHospitalizationId) return;
                context.pushReplacement(
                  '/hospitalizations/${p.hospitalizationId}',
                );
              },
            ),
        ],
      ),
    );
  }
}

class _TimelineHeader extends StatelessWidget {
  const _TimelineHeader({
    required this.patient,
    required this.showSummaries,
    this.record,
  });
  final Patient patient;
  final AuthorizedClinicalRecord? record;
  final bool showSummaries;

  @override
  Widget build(BuildContext context) {
    final fhirPatient = record?.patient;
    final birth = fhirPatient?.birthDate;
    final closed =
        patient.hospitalizationStatus == 'discharged' ||
        record?.hospitalization.status == 'discharged';
    final active =
        patient.hospitalizationStatus == 'admitted' &&
        record?.hospitalization.status == 'admitted';
    final absent = patient.hospitalizationStatus == 'temporarily_absent';
    final age = birth != null ? _ageAt(birth) : patientAge(patient.birthDate);
    final day = hospitalizationDay(patient);
    final subtitle = [
      if (age != null) '$age años',
      if (day != null) 'Día $day',
    ].join(' · ');
    final service = patient.unitDisplayName ?? record?.hospitalization.unit;
    final allergies = [
      for (final entry
          in record?.entriesOf(ClinicalSectionType.allergies) ??
              const <ClinicalRecordEntry>[])
        entry.title,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClinicalCard(
            radius: ClinicalRadii.large,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClinicalAvatar(
                              initials: clinicalInitials(patient.fullName),
                              size: 64,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              patient.fullName,
                              style: const TextStyle(
                                fontSize: 24,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                                color: ClinicalColors.ink,
                              ),
                            ),
                            if (subtitle.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                subtitle,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: ClinicalColors.secondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: ClinicalBadge(
                          label: closed
                              ? 'Cerrada · Solo lectura'
                              : active
                              ? 'Hospitalización activa'
                              : patient.hospitalizationStatus == 'planned'
                              ? 'Planificada'
                              : absent
                              ? 'Ausencia temporal'
                              : 'Estado no confirmado',
                          color: active
                              ? ClinicalColors.softMint
                              : absent
                              ? ClinicalColors.softAttention
                              : ClinicalColors.fillSubtle,
                          textColor: active
                              ? ClinicalColors.mintText
                              : absent
                              ? ClinicalColors.attention
                              : ClinicalColors.secondary,
                          icon: closed
                              ? Icons.lock_outline_rounded
                              : active
                              ? Icons.check_circle_outline_rounded
                              : absent
                              ? Icons.schedule_rounded
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    children: [
                      if (birth != null)
                        _InfoRow('Nacimiento', _dateOnly(birth))
                      else if (patient.birthDate != null)
                        _InfoRow(
                          'Nacimiento',
                          formatClinicalDate(patient.birthDate),
                        ),
                      if (service != null) _InfoRow('Servicio', service),
                      _InfoRow(
                        'Ingreso',
                        formatClinicalDay(patient.admittedAt),
                      ),
                      if (record?.hospitalization.attendingPhysician != null)
                        _InfoRow(
                          'Médico tratante',
                          record!.hospitalization.attendingPhysician!,
                        ),
                      _InfoRow(
                        'Ubicación',
                        patient.locationLabel.replaceFirst(
                          RegExp(r'^Cama\s+Cama\s+', caseSensitive: false),
                          'Cama ',
                        ),
                      ),
                      if (closed)
                        _InfoRow(
                          'Egreso',
                          patient.dischargedAt == null
                              ? 'sin fecha registrada'
                              : formatClinicalDate(patient.dischargedAt),
                        ),
                    ],
                  ),
                ),
                if (record != null) ...[
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _DetailRow(
                          'Motivo de hospitalización',
                          record!.hospitalization.reason ??
                              'Sin información registrada',
                        ),
                        _DetailRow(
                          'Alergias conocidas',
                          allergies.isEmpty
                              ? 'Sin información registrada'
                              : allergies.join(', '),
                          highlight: allergies.isNotEmpty,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: RelevantObservations(record: record!),
                  ),
                ],
                const Divider(height: 1, indent: 16, endIndent: 16),
                _HeaderLink(
                  icon: Icons.medical_information_outlined,
                  label: 'Ver ficha clínica',
                  onTap: () => context.push(
                    '/hospitalizations/${patient.hospitalizationId}/record',
                  ),
                ),
                if (showSummaries) ...[
                  const Divider(height: 1, indent: 58, endIndent: 16),
                  _HeaderLink(
                    icon: Icons.summarize_outlined,
                    label: 'Resúmenes',
                    onTap: () => context.push(
                      '/hospitalizations/${patient.hospitalizationId}/summaries',
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (record?.truncated == true || record?.status == 'partial')
            const _IncompleteWarning(
              'La ficha clínica está incompleta: la fuente entregó información parcial.',
            ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: $value',
    excludeSemantics: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: ClinicalColors.secondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: ClinicalColors.ink,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value, {this.highlight = false});
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: ClinicalTextStyles.footnote),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: highlight ? ClinicalColors.destructive : ClinicalColors.ink,
          ),
        ),
      ],
    ),
  );
}

class _HeaderLink extends StatelessWidget {
  const _HeaderLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: ClinicalColors.softMint,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 17, color: ClinicalColors.mintDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 16, color: ClinicalColors.ink),
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: ClinicalColors.tertiary,
          ),
        ],
      ),
    ),
  );
}

/// Filtros de la bitácora del diseño Figma: por categoría del evento o por
/// profesión del autor. Los registros FHIR se ubican por tipo de recurso.
enum _BitacoraFilter {
  all('Todos'),
  clinical('Clínica'),
  medicine('Medicina'),
  vitals('Signos vitales'),
  procedures('Procedimientos'),
  nursing('Enfermería'),
  tens('TENS'),
  kinesiology('Kinesiología'),
  nutrition('Nutrición'),
  medications('Medicamentos'),
  communication('Comunicación');

  const _BitacoraFilter(this.label);
  final String label;

  Profession? get profession => switch (this) {
    _BitacoraFilter.medicine => Profession.medicina,
    _BitacoraFilter.nursing => Profession.enfermeria,
    _BitacoraFilter.tens => Profession.tens,
    _BitacoraFilter.kinesiology => Profession.kinesiologia,
    _BitacoraFilter.nutrition => Profession.nutricion,
    _ => null,
  };

  Set<EventCategory> get categories => switch (this) {
    _BitacoraFilter.clinical => {EventCategory.notaClinica},
    _BitacoraFilter.vitals => {EventCategory.signosVitales},
    _BitacoraFilter.procedures => {EventCategory.procedimiento},
    _BitacoraFilter.medications => {EventCategory.farmacologia},
    _BitacoraFilter.communication => {EventCategory.comunicacion},
    _ => const {},
  };

  /// Whether a timeline row belongs to this filter.
  bool accepts(_Row row) {
    if (this == _BitacoraFilter.all) return true;
    final profession = this.profession;
    if (profession != null) return row.profession == profession;
    return row.category != null && categories.contains(row.category);
  }
}

/// One row of the bitácora with the data its filters need.
class _Row {
  const _Row({
    required this.id,
    required this.child,
    this.time,
    this.dateOnly,
    this.category,
    this.profession,
  });
  final String id;
  final DateTime? time;
  final String? dateOnly;
  final EventCategory? category;
  final Profession? profession;
  final Widget child;
}

/// Figma category of a FHIR timeline item.
EventCategory _fhirCategory(String resourceType) => switch (resourceType) {
  'Observation' => EventCategory.signosVitales,
  'Procedure' => EventCategory.procedimiento,
  'MedicationRequest' ||
  'MedicationStatement' ||
  'MedicationAdministration' => EventCategory.farmacologia,
  _ => EventCategory.notaClinica,
};

class _TimelineGroups extends StatefulWidget {
  const _TimelineGroups({
    required this.hospitalizationId,
    required this.fhirItems,
    required this.events,
    this.record,
  });
  final String hospitalizationId;
  final AuthorizedClinicalRecord? record;
  final List<ClinicalTimelineItem> fhirItems;
  final List<ClinicalEvent> events;

  @override
  State<_TimelineGroups> createState() => _TimelineGroupsState();
}

class _TimelineGroupsState extends State<_TimelineGroups> {
  _BitacoraFilter _filter = _BitacoraFilter.all;

  /// Photos indexed by what they belong to (note client id or entry id).
  Map<String, String> _photos() => {
    for (final photo
        in widget.record?.entriesOf(ClinicalSectionType.photos) ??
            const <ClinicalRecordEntry>[])
      if (photo.noteRef != null) photo.noteRef!: photo.resourceId,
  };

  Widget? _photo(String? reference, Map<String, String> photos) {
    final documentId = reference == null ? null : photos[reference];
    return documentId == null
        ? null
        : ClinicalPhotoAttachment(
            hospitalizationId: widget.hospitalizationId,
            documentId: documentId,
          );
  }

  @override
  Widget build(BuildContext context) {
    final photos = _photos();
    final rows = <_Row>[];
    final seen = <String>{};
    for (final item in widget.fhirItems) {
      final key = 'FHIR:${item.id}';
      if (!seen.add(key)) continue;
      final hasDateOnlyPrecision = item.precision == 'date';
      final category = _fhirCategory(item.resourceType);
      rows.add(
        _Row(
          id: key,
          time: item.occurredAt == null || hasDateOnlyPrecision
              ? null
              : DateTime.tryParse(item.occurredAt!),
          dateOnly: hasDateOnlyPrecision ? item.occurredAt : null,
          category: category,
          child: TimelineEntryCard(
            title: item.title,
            category: _resourceLabel(item.resourceType),
            date: item.occurredAt,
            detail: item.detail,
            dateOnly: hasDateOnlyPrecision,
            attachment: _photo(item.id, photos),
          ),
        ),
      );
    }
    for (final event in widget.events) {
      final key = '${event.sourceKind}:${event.id}';
      if (!seen.add(key)) continue;
      final category = event.isMilestone
          ? EventCategory.fromWire(event.category) ?? EventCategory.notaClinica
          : null;
      final profession = Profession.fromWire(event.authorProfession);
      rows.add(
        _Row(
          id: key,
          time: event.occurredAt,
          category: category,
          profession: profession,
          child: TimelineEntryCard(
            title: event.summary,
            category: event.isMilestone
                ? category!.label
                : _eventLabel(event.kind),
            tint: category?.tint,
            date: event.occurredAt.toIso8601String(),
            dateOnly: false,
            author: event.isMilestone ? event.authorDisplayName : null,
            role: profession?.roleLabel,
            isNote: event.isMilestone,
            attachment: _photo(event.clientEventId, photos),
          ),
        ),
      );
    }
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(ClinicalSpacing.page),
        child: Text('No hay eventos disponibles.'),
      );
    }
    final visible = rows.where(_filter.accepts).toList();
    final dated = visible.where((row) => row.time != null).toList()
      ..sort((a, b) {
        final byTime = b.time!.compareTo(a.time!);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    final dateOnlyRows = visible.where((row) => row.dateOnly != null).toList()
      ..sort((a, b) {
        final byDate = b.dateOnly!.compareTo(a.dateOnly!);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });
    final undated =
        visible
            .where((row) => row.time == null && row.dateOnly == null)
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    final record = widget.record;
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: ClinicalColors.mint,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Hoy · Turno ${clinicalShiftLabel(now)}',
                  style: ClinicalTextStyles.footnote,
                ),
              ),
            ],
          ),
        ),
        ClinicalPillRow(
          children: [
            for (final filter in _BitacoraFilter.values)
              ClinicalFilterPill(
                label: filter.label,
                selected: _filter == filter,
                onTap: () => setState(() => _filter = filter),
              ),
          ],
        ),
        if (record != null && _filter == _BitacoraFilter.medications)
          MedicationScheduleCard(record: record),
        if (record != null && _filter == _BitacoraFilter.nutrition)
          FluidBalanceCard(record: record),
        const SizedBox(height: ClinicalSpacing.compact),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text(
                'Sin eventos en esta categoría',
                style: TextStyle(fontSize: 15, color: ClinicalColors.tertiary),
              ),
            ),
          ),
        for (var index = 0; index < dated.length; index++) ...[
          if (index == 0 ||
              formatClinicalDay(dated[index].time!) !=
                  formatClinicalDay(dated[index - 1].time!))
            _DayHeader(formatClinicalDay(dated[index].time!)),
          dated[index].child,
        ],
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

class _DayHeader extends StatelessWidget {
  const _DayHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      ClinicalSpacing.page,
      ClinicalSpacing.item,
      ClinicalSpacing.page,
      ClinicalSpacing.compact,
    ),
    child: Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: ClinicalColors.mint,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ClinicalColors.secondary,
            ),
          ),
        ),
      ],
    ),
  );
}

String _resourceLabel(String type) => switch (type) {
  'Observation' => 'Observación',
  'DiagnosticReport' => 'Informe',
  'MedicationRequest' || 'MedicationStatement' => 'Medicación',
  'Condition' => 'Condición',
  'Procedure' => 'Procedimiento',
  'AllergyIntolerance' => 'Alergia',
  _ => 'Registro clínico',
};

String _eventLabel(String kind) => switch (kind) {
  'observation' => 'Observación',
  'condition' => 'Condición',
  'medication' => 'Medicación',
  _ => 'Registro clínico',
};

class _IncompleteWarning extends StatelessWidget {
  const _IncompleteWarning(this.message, {this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: ClinicalSpacing.compact,
    ),
    child: Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: ClinicalColors.softAttention,
        borderRadius: BorderRadius.circular(ClinicalRadii.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: ClinicalColors.attention,
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    ),
  );
}

String _dateOnly(String raw) => raw.split('-').reversed.join('-');
int? _ageAt(String raw) {
  final parts = raw.split('-').map(int.tryParse).toList();
  if (parts.length != 3 || parts.any((part) => part == null)) return null;
  return patientAge(DateTime(parts[0]!, parts[1]!, parts[2]!));
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
                  padding: const EdgeInsets.all(16),
                  children: [
                    ClinicalCard(
                      radius: ClinicalRadii.large,
                      child: Column(
                        children: [
                          ListTile(
                            leading: ClinicalAvatar(
                              initials: clinicalInitials(item.fullName),
                            ),
                            title: Text(item.fullName),
                            subtitle: Text(item.locationLabel),
                          ),
                          const Divider(height: 1, indent: 16),
                          ListTile(
                            title: const Text('Nacimiento'),
                            subtitle: Text(formatClinicalDate(item.birthDate)),
                          ),
                          const Divider(height: 1, indent: 16),
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
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
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
