import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/clinical_design_system.dart';
import '../../../core/design_system/anchored_selector.dart';
import '../../../core/time/clinical_time.dart';
import '../../institutional/data/iam_models.dart';
import '../../institutional/data/iam_repository.dart';
import '../../institutional/presentation/iam_providers.dart';

class AssignmentsScreen extends ConsumerStatefulWidget {
  const AssignmentsScreen({super.key});

  @override
  ConsumerState<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends ConsumerState<AssignmentsScreen> {
  /// El texto vive en el State y no en el campo: una recarga de permisos
  /// remonta la lista, y el campo debe conservar lo escrito y el foco.
  final _patientSearchController = TextEditingController();
  var _patientQuery = '';

  @override
  void dispose() {
    _patientSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iamState = ref.watch(iamContextProvider);
    final iam = iamState.valueOrNull;
    final permission = iam?.allows('clinical.assignment.manage') ?? false;
    final assignments = ref.watch(careAssignmentsProvider);
    final eligible = ref.watch(eligibleMembersProvider);
    if (!permission) {
      return Scaffold(
        appBar: clinicalBackAppBar(
          context,
          title: 'Profesionales por hospitalización',
          fallbackLocation: '/settings',
          tooltip: 'Volver a Ajustes',
        ),
        body: const Center(
          child: Text('No tienes permiso para gestionar asignaciones.'),
        ),
      );
    }
    return Scaffold(
      appBar: clinicalBackAppBar(
        context,
        title: 'Profesionales por hospitalización',
        fallbackLocation: '/settings',
        tooltip: 'Volver a Ajustes',
      ),
      body: Container(
        color: ClinicalColors.canvas,
        padding: const EdgeInsets.fromLTRB(
          ClinicalSpacing.page,
          ClinicalSpacing.page,
          ClinicalSpacing.page,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: ClinicalSpacing.card),
              child: TextField(
                controller: _patientSearchController,
                decoration: clinicalInputDecoration(
                  labelText: 'Nombre o UUID de hospitalización',
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _patientQuery = value),
              ),
            ),
            Expanded(
              child: assignments.when(
                skipLoadingOnRefresh: false,
                skipError: false,
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) =>
                    _error(ref, 'No fue posible cargar las hospitalizaciones.'),
                data: (items) => eligible.when(
                  skipLoadingOnRefresh: false,
                  skipError: false,
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) => _error(
                    ref,
                    'No fue posible cargar profesionales elegibles.',
                  ),
                  data: (members) {
                    final names = ref.watch(careAssignmentPatientNamesProvider);
                    return _AssignmentList(
                      items: items,
                      members: members,
                      patientNames: names is AsyncData<Map<String, String>>
                          ? names.value
                          : const {},
                      patientQuery: _patientQuery,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _error(WidgetRef ref, String message) => Center(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(message),
      TextButton(
        onPressed: () {
          ref.invalidate(careAssignmentsProvider);
          ref.invalidate(careAssignmentPatientNamesProvider);
          ref.invalidate(eligibleMembersProvider);
        },
        child: const Text('Reintentar'),
      ),
    ],
  ),
);

class _AssignmentList extends ConsumerWidget {
  const _AssignmentList({
    required this.items,
    required this.members,
    required this.patientNames,
    required this.patientQuery,
  });
  final List<CareAssignmentRecord> items;
  final List<EligibleMember> members;
  final Map<String, String> patientNames;
  final String patientQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iam = ref.watch(iamContextProvider).valueOrNull;
    if (iam == null) return const Center(child: CircularProgressIndicator());
    final episodes = <String, List<CareAssignmentRecord>>{};
    for (final item in items) {
      episodes.putIfAbsent(item.hospitalizationId, () => []).add(item);
    }
    final query = patientQuery.trim().toLowerCase();
    final visibleEpisodes = episodes.entries.where((entry) {
      if (query.isEmpty) return true;
      final patientName = patientNames[entry.key]?.toLowerCase() ?? '';
      return patientName.contains(query) ||
          entry.key.toLowerCase().contains(query);
    });
    return ListView(
      padding: const EdgeInsets.only(bottom: ClinicalSpacing.page),
      children: [
        for (final entry in visibleEpisodes)
          _HospitalizationCard(
            hospitalizationId: entry.key,
            rows: entry.value,
            members: members,
            patientName: patientNames[entry.key],
            organizationId: iam.organizationId,
          ),
        if (items.isEmpty || visibleEpisodes.isEmpty)
          const ListTile(title: Text('No hay hospitalizaciones disponibles.')),
      ],
    );
  }
}

class _HospitalizationCard extends ConsumerWidget {
  const _HospitalizationCard({
    required this.hospitalizationId,
    required this.rows,
    required this.members,
    required this.patientName,
    required this.organizationId,
  });
  final String hospitalizationId;
  final List<CareAssignmentRecord> rows;
  final List<EligibleMember> members;
  final String? patientName;
  final String organizationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final episode = rows.first;
    final now = DateTime.now().toUtc();
    final activeMemberships = rows
        .where((row) {
          return row.assignmentId != null &&
              row.membershipId != null &&
              row.revokedAt == null &&
              (row.validFrom == null || !row.validFrom!.toUtc().isAfter(now)) &&
              (row.validUntil == null || row.validUntil!.toUtc().isAfter(now));
        })
        .map((row) => row.membershipId)
        .toSet();
    final targets = members
        .where((member) => !activeMemberships.contains(member.membershipId))
        .toList();
    final assignmentsByMember = <String, List<CareAssignmentRecord>>{};
    for (final row in rows.where((row) => row.assignmentId != null)) {
      assignmentsByMember
          .putIfAbsent(row.membershipId ?? row.assignmentId!, () => [])
          .add(row);
    }
    for (final history in assignmentsByMember.values) {
      history.sort((a, b) {
        final first = a.validFrom;
        final second = b.validFrom;
        if (first == null || second == null) {
          if (first != null) return 1;
          if (second != null) return -1;
        } else {
          final byDate = first.compareTo(second);
          if (byDate != 0) return byDate;
        }
        return a.assignmentId!.compareTo(b.assignmentId!);
      });
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: ClinicalSpacing.item),
      child: ClinicalCard(
        radius: ClinicalRadii.card,
        padding: const EdgeInsets.all(ClinicalSpacing.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              patientName?.isNotEmpty == true
                  ? patientName!
                  : 'Hospitalización',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: ClinicalSpacing.compact),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Admisión ${formatClinicalDateTime(episode.admittedAt)}',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: ClinicalColors.secondary),
                ),
                Text(
                  _hospitalizationStatusLabel(episode.status),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: ClinicalColors.secondary),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    hospitalizationId,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
                IconButton(
                  tooltip: 'Copiar identificador del episodio',
                  icon: const Icon(Icons.copy),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: hospitalizationId)),
                ),
              ],
            ),
            if (assignmentsByMember.isNotEmpty) ...[
              const SizedBox(height: ClinicalSpacing.compact),
              const ClinicalSectionTitle('Profesionales asignados'),
              for (final (index, history)
                  in assignmentsByMember.values.indexed) ...[
                if (index > 0) const SizedBox(height: ClinicalSpacing.item),
                _MemberAssignmentHistory(
                  history: history,
                  members: members,
                  organizationId: organizationId,
                  now: now,
                ),
              ],
            ],
            const SizedBox(height: ClinicalSpacing.section),
            OutlinedButton.icon(
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Asignar profesional'),
              onPressed: () =>
                  _grant(context, ref, organizationId, episode, targets),
            ),
          ],
        ),
      ),
    );
  }
}

String _hospitalizationStatusLabel(String status) => switch (status) {
  'planned' => 'Hospitalización planificada',
  'admitted' => 'Hospitalización vigente',
  'temporarily_absent' => 'Hospitalización con ausencia temporal',
  'discharged' => 'Hospitalización egresada',
  'cancelled' => 'Hospitalización cancelada',
  'entered_in_error' => 'Hospitalización registrada por error',
  _ => 'Estado de hospitalización: $status',
};

class _MemberAssignmentHistory extends ConsumerWidget {
  const _MemberAssignmentHistory({
    required this.history,
    required this.members,
    required this.organizationId,
    required this.now,
  });

  final List<CareAssignmentRecord> history;
  final List<EligibleMember> members;
  final String organizationId;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = _memberName(history.first, members);
    final revocable = history.where((row) => row.revokedAt == null).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: ClinicalSpacing.compact),
                  for (final (index, row) in history.indexed) ...[
                    if (index > 0)
                      const SizedBox(height: ClinicalSpacing.compact),
                    _AssignmentPeriod(row: row, now: now),
                  ],
                  if (history.any(
                    (row) => row.assigneeMembershipStatus == 'suspended',
                  ))
                    Text(
                      'Sin acceso · Membresía suspendida',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: ClinicalColors.secondary),
                    ),
                ],
              ),
            ),
            if (revocable.isNotEmpty)
              _revokeButton(context, ref, organizationId, revocable, name),
          ],
        ),
      ],
    );
  }
}

class _AssignmentPeriod extends StatelessWidget {
  const _AssignmentPeriod({required this.row, required this.now});

  final CareAssignmentRecord row;
  final DateTime now;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Asignado el ${row.validFrom == null ? 'No registrada' : formatClinicalDateTime(row.validFrom!)}',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      if (row.revokedAt != null)
        Text(
          'Revocado el ${formatClinicalDateTime(row.revokedAt!)}',
          style: Theme.of(context).textTheme.bodyMedium,
        )
      else if (row.validUntil != null && !row.validUntil!.toUtc().isAfter(now))
        Text(
          'Finalizada el ${formatClinicalDateTime(row.validUntil!)}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
    ],
  );
}

Widget _revokeButton(
  BuildContext context,
  WidgetRef ref,
  String organizationId,
  List<CareAssignmentRecord> revocable,
  String name,
) => IconButton(
  tooltip: 'Quitar acceso',
  icon: const Icon(Icons.person_remove_outlined),
  style: IconButton.styleFrom(foregroundColor: ClinicalColors.destructive),
  onPressed: () =>
      _confirmRevoke(context, ref, organizationId, revocable, name),
);

Future<void> _confirmRevoke(
  BuildContext context,
  WidgetRef ref,
  String organizationId,
  List<CareAssignmentRecord> revocable,
  String name,
) async {
  var row = revocable.last;
  if (revocable.length > 1) {
    final selected = await showDialog<CareAssignmentRecord>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Seleccionar asignación'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final candidate in revocable.reversed)
                ListTile(
                  title: Text(
                    candidate.validFrom == null
                        ? 'Asignación sin fecha'
                        : 'Asignado el ${formatClinicalDateTime(candidate.validFrom!)}',
                  ),
                  onTap: () => Navigator.pop(dialogContext, candidate),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (selected == null || !context.mounted) return;
    row = selected;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Quitar acceso'),
      content: Text(
        'Se revocará la asignación de $name iniciada el ${row.validFrom == null ? 'día no registrado' : formatClinicalDateTime(row.validFrom!)}. Si está vigente, se quitará el acceso a la información de esta hospitalización que concede esta asignación.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: ClinicalColors.destructive,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Quitar acceso'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await _apply(
    context,
    ref,
    (attempt) => ref
        .read(iamRepositoryProvider)
        .revokeCareAssignment(
          organizationId: organizationId,
          assignmentId: row.assignmentId!,
          attempt: attempt,
        ),
  );
}

String _memberName(CareAssignmentRecord row, List<EligibleMember> members) =>
    row.assigneeDisplayName ??
    members
        .where((member) => member.membershipId == row.membershipId)
        .map((member) => member.displayName)
        .firstOrNull ??
    'Profesional asignado';

Future<void> _grant(
  BuildContext context,
  WidgetRef ref,
  String organizationId,
  CareAssignmentRecord hospitalization,
  List<EligibleMember> members,
) async {
  if (members.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No hay profesionales elegibles.')),
    );
    return;
  }
  var selected = members.first.membershipId;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        scrollable: true,
        title: const Text('Asignar profesional'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SizedBox(
            width: (MediaQuery.sizeOf(dialogContext).width - 80).clamp(
              200.0,
              440.0,
            ),
            child: AnchoredSelector<String>(
              selectedValue: selected,
              labelText: 'Profesional',
              options: [
                for (final member in members)
                  AnchoredSelectorOption(
                    value: member.membershipId,
                    label: member.displayName,
                  ),
              ],
              onSelected: (value) => setState(() => selected = value),
              decoration: clinicalInputDecoration(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Asignar'),
          ),
        ],
      ),
    ),
  );
  if (accepted != true || !context.mounted) return;
  await _apply(
    context,
    ref,
    (attempt) => ref
        .read(iamRepositoryProvider)
        .grantCareAssignment(
          organizationId: organizationId,
          hospitalizationId: hospitalization.hospitalizationId,
          membershipId: selected,
          attempt: attempt,
        ),
    usesValidFrom: true,
  );
}

Future<void> _apply(
  BuildContext context,
  WidgetRef ref,
  Future<AdminOperationResult> Function(AdminOperationAttempt) action, {
  AdminOperationAttempt? attempt,
  bool usesValidFrom = false,
}) async {
  attempt ??= newAdminOperationAttempt(usesValidFrom: usesValidFrom);
  try {
    final result = await action(attempt);
    if (!context.mounted) return;
    if (result.success) {
      invalidateAuthorizationAndData(ref);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Asignación actualizada.')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No fue posible aplicar el cambio.')),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No fue posible aplicar el cambio. Puedes reintentar.'),
          action: SnackBarAction(
            label: 'Reintentar',
            onPressed: () => _apply(context, ref, action, attempt: attempt),
          ),
        ),
      );
    }
  }
}
