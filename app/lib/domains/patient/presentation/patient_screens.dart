import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/design_system/clinical_design_system.dart';
import '../../../core/router/administration_navigation.dart';
import '../../../core/time/clinical_time.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../clinical_event/domain/entities/clinical_event.dart';
import '../../clinical_event/presentation/clinical_event_providers.dart';
import '../../context_note/presentation/context_note_providers.dart';
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
          Expanded(
            child: result.when(
              skipLoadingOnRefresh: false,
              skipError: false,
              loading: () => const Center(child: CircularProgressIndicator()),
              error:
                  (_, __) => const Center(
                    child: Text('No fue posible cargar las hospitalizaciones.'),
                  ),
              data: (items) {
                final visible =
                    items.where((item) => item.matchesSearch(query)).toList();
                if (visible.isEmpty) {
                  return RefreshIndicator(
                    onRefresh:
                        () => ref
                            .refresh(patientsProvider.future)
                            .then<void>((_) {}),
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
                  onRefresh:
                      () => ref
                          .refresh(patientsProvider.future)
                          .then<void>((_) {}),
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
        actions:
            canAddMilestone && patient.valueOrNull != null
                ? [
                  IconButton(
                    tooltip: 'Agregar hito',
                    icon: const Icon(Icons.add_task_outlined),
                    onPressed: () {
                      final item = patient.valueOrNull;
                      if (item == null) return;
                      showMilestoneEditorSheet(
                        context,
                        patient: item,
                        onSaved:
                            () => ref.invalidate(
                              hospitalizationClinicalEventsProvider(
                                hospitalizationId,
                              ),
                            ),
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
        error:
            (_, __) => const Center(
              child: Text('No fue posible cargar la hospitalización.'),
            ),
        data:
            (item) =>
                item == null
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
            hospitalizationClinicalEventsProvider(
              patient.hospitalizationId,
            ).future,
          ),
        ]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ListTile(
            title: Text(patient.fullName),
            subtitle: Text(patient.locationLabel),
            onTap:
                () => context.go(
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
            error:
                (_, __) => const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No fue posible cargar los eventos.'),
                ),
            data:
                (items) =>
                    items.isEmpty
                        ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('No hay eventos clínicos disponibles.'),
                        )
                        : Column(
                          children: [
                            for (final event in items)
                              _TimelineRow(event: event),
                          ],
                        ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends ConsumerStatefulWidget {
  const _TimelineRow({required this.event});
  final ClinicalEvent event;

  @override
  ConsumerState<_TimelineRow> createState() => _TimelineRowState();
}

class _TimelineRowState extends ConsumerState<_TimelineRow> {
  AudioPlayer? _player;
  bool _loadingAudio = false;
  bool _playing = false;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    final player = _player ??= AudioPlayer();
    if (_playing) {
      await player.pause();
      setState(() => _playing = false);
      return;
    }
    setState(() => _loadingAudio = true);
    try {
      if (player.duration == null) {
        final url = await ref
            .read(contextNoteRepositoryProvider)
            .signedAudioUrl(widget.event.audioStoragePath!);
        await player.setUrl(url);
      }
      await player.play();
      setState(() => _playing = true);
    } catch (_) {
      // A failed playback keeps the row stable; the icon offers a retry.
    } finally {
      if (mounted) setState(() => _loadingAudio = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final isAudioMilestone = event.isStoredAudioMilestone;
    final isMilestone = event.sourceKind == 'context_note';
    final subtitle =
        isAudioMilestone
            ? '${event.kind} · ${formatClinicalDateTime(event.occurredAt)} · ${_formatDuration(event.audioDurationMs ?? 0)}'
            : '${event.kind} · ${formatClinicalDateTime(event.occurredAt)}';
    return ListTile(
      leading: isMilestone ? const Icon(Icons.flag_outlined) : null,
      title: Text(event.summary),
      subtitle: Text(subtitle),
      trailing:
          isAudioMilestone
              ? _loadingAudio
                  ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : IconButton(
                    tooltip: _playing ? 'Detener audio' : 'Reproducir audio',
                    onPressed: _togglePlayback,
                    icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
                  )
              : null,
    );
  }

  String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
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
        error:
            (_, __) => const Center(
              child: Text('No fue posible cargar la información.'),
            ),
        data:
            (item) =>
                item == null
                    ? const Center(child: Text('Paciente no encontrado.'))
                    : RefreshIndicator(
                      onRefresh:
                          () => ref
                              .refresh(
                                patientProvider(hospitalizationId).future,
                              )
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

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iam = ref.watch(iamContextProvider);
    final session = ref.watch(sessionProvider);
    return Scaffold(
      bottomNavigationBar: const ClinicalBottomNavigation(selectedIndex: 1),
      appBar: clinicalAppBar(title: 'Ajustes'),
      body: iam.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (_, __) =>
                const Center(child: Text('No fue posible cargar el perfil.')),
        data: (profile) {
          if (profile == null) {
            return const Center(
              child: Text('No fue posible cargar el perfil.'),
            );
          }
          final administrationDestinations = administrationNavigationFor(
            profile,
          );
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ClinicalProfileCard(
                initials: _initials(profile.displayName),
                name: profile.displayName,
                subtitle: profile.organizationName,
                status:
                    profile.profileStatus == 'active' &&
                            profile.membershipStatus == 'active'
                        ? 'Activo'
                        : 'Suspendido',
              ),
              if (administrationDestinations.isNotEmpty) ...[
                const SizedBox(height: 18),
                ClinicalSettingsSection(
                  title: 'Administración institucional',
                  children: [
                    for (var i = 0; i < administrationDestinations.length; i++)
                      ClinicalSettingsRow(
                        label: administrationDestinations[i].label,
                        icon: switch (administrationDestinations[i].location) {
                          '/users' => Icons.group_outlined,
                          '/roles' => Icons.admin_panel_settings_outlined,
                          _ => Icons.assignment_ind_outlined,
                        },
                        isLast: i == administrationDestinations.length - 1,
                        onTap:
                            () => context.go(
                              administrationDestinations[i].location,
                            ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
              ],
              ClinicalSettingsSection(
                title: 'Perfil institucional',
                children: [
                  ClinicalSettingsRow(
                    label: 'Nombre',
                    value: profile.displayName,
                    icon: Icons.person_outline,
                  ),
                  ClinicalSettingsRow(
                    label: 'Organización',
                    value: profile.organizationName,
                    icon: Icons.business_outlined,
                  ),
                  ClinicalSettingsRow(
                    label: 'Estado de perfil',
                    value: profile.profileStatus,
                    icon: Icons.verified_outlined,
                  ),
                  ClinicalSettingsRow(
                    label: 'Estado de membresía',
                    value: profile.membershipStatus,
                    icon: Icons.groups_outlined,
                    isLast: true,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ClinicalSettingsSection(
                title: 'Seguridad',
                children: [
                  ClinicalSettingsRow(
                    label: 'Correo institucional',
                    value: session?.user.email ?? 'No disponible',
                    icon: Icons.mail_outline,
                    isLast: true,
                  ),
                ],
              ),
              ClinicalSettingsRow(
                label: 'Cerrar sesión',
                icon: Icons.logout,
                destructive: true,
                onTap: () => ref.read(authRepositoryProvider).signOut(),
                isLast: true,
              ),
            ],
          );
        },
      ),
    );
  }
}

String _initials(String name) =>
    name
        .split(' ')
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0])
        .join();
