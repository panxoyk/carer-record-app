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
              error: (_, __) => const Center(
                child: Text('No fue posible cargar las hospitalizaciones.'),
              ),
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
                          subtitle: Text(item.locationLabel),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            final canReadTimeline =
                                iamContext.valueOrNull?.allows(
                                  'clinical.timeline.read',
                                ) ??
                                false;
                            context.go(
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
}

class PatientDetailScreen extends ConsumerWidget {
  const PatientDetailScreen({required this.hospitalizationId, super.key});
  final String hospitalizationId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patient = ref.watch(patientProvider(hospitalizationId));
    final iam = ref.watch(iamContextProvider).valueOrNull;
    // UI guard only: RLS on context_notes remains the authorization authority.
    final canAddMilestone =
        (iam?.allows('context.note.create') ?? false) &&
        (iam?.allows('context.note.confirm') ?? false);
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
        error: (_, __) => const Center(
          child: Text('No fue posible cargar la hospitalización.'),
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
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          ref.refresh(patientProvider(patient.hospitalizationId).future),
          ref.refresh(
            hospitalizationClinicalEventsProvider(patient.hospitalizationId)
                .future,
          ),
        ]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ListTile(
            title: Text(patient.fullName),
            subtitle: Text(patient.locationLabel),
            onTap: () => context.go(
              '/hospitalizations/${patient.hospitalizationId}/details',
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('EVENTOS CLÍNICOS'),
          ),
          events.when(
            skipLoadingOnRefresh: false,
            skipError: false,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No fue posible cargar los eventos.'),
            ),
            data: (items) => items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No hay eventos clínicos disponibles.'),
                  )
                : Column(
                    children: [
                      for (final event in items) _TimelineRow(event: event),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// A confirmed milestone is shown as the text its author approved. ADR-016
/// withdrew the stored-audio provision, so there is nothing to play here.
class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.event});

  final ClinicalEvent event;

  @override
  Widget build(BuildContext context) {
    final marker = event.isDictatedMilestone ? 'Dictado local' : event.kind;
    final subtitle = '$marker · ${formatClinicalDateTime(event.occurredAt)}';
    return ListTile(
      leading: event.isMilestone ? const Icon(Icons.flag_outlined) : null,
      title: Text(event.summary),
      subtitle: Text(subtitle),
    );
  }
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
                  ],
                ),
              ),
      ),
    );
  }
}
