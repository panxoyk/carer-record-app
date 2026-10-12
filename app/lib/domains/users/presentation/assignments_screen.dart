import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/design_system/clinical_design_system.dart';
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
  var _patientQuery = '';

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
          title: 'Asignaciones asistenciales',
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
        title: 'Asignaciones asistenciales',
        fallbackLocation: '/settings',
        tooltip: 'Volver a Ajustes',
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Buscar por nombre del paciente',
                helperText:
                    'Sin acceso a nombres, busca por identificador del episodio.',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _patientQuery = value),
            ),
          ),
          Expanded(
            child: assignments.when(
              skipLoadingOnRefresh: false,
              skipError: false,
              loading: () => const Center(child: CircularProgressIndicator()),
              error:
                  (_, __) => _error(
                    ref,
                    'No fue posible cargar las hospitalizaciones.',
                  ),
              data:
                  (items) => eligible.when(
                    skipLoadingOnRefresh: false,
                    skipError: false,
                    loading:
                        () => const Center(child: CircularProgressIndicator()),
                    error:
                        (_, __) => _error(
                          ref,
                          'No fue posible cargar profesionales elegibles.',
                        ),
                    data: (members) {
                      final names = ref.watch(
                        careAssignmentPatientNamesProvider,
                      );
                      return _AssignmentList(
                        items: items,
                        members: members,
                        patientNames:
                            names is AsyncData<Map<String, String>>
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
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
    final activeMemberships =
        rows
            .where((row) {
              return row.assignmentId != null &&
                  row.membershipId != null &&
                  row.revokedAt == null &&
                  (row.validFrom == null ||
                      !row.validFrom!.toUtc().isAfter(now)) &&
                  (row.validUntil == null ||
                      row.validUntil!.toUtc().isAfter(now));
            })
            .map((row) => row.membershipId)
            .toSet();
    final targets =
        members
            .where((member) => !activeMemberships.contains(member.membershipId))
            .toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClinicalCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: Text(
                patientName?.isNotEmpty == true
                    ? patientName!
                    : 'Hospitalización',
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${episode.status} · ingreso ${formatClinicalDateTime(episode.admittedAt)}',
                  ),
                  Text(
                    hospitalizationId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              isThreeLine: true,
              leading: IconButton(
                tooltip: 'Copiar identificador del episodio',
                icon: const Icon(Icons.copy),
                onPressed:
                    () => Clipboard.setData(
                      ClipboardData(text: hospitalizationId),
                    ),
              ),
            ),
            for (final row in rows.where((row) => row.assignmentId != null))
              ListTile(
                title: Text(_memberName(row, members)),
                subtitle:
                    row.assigneeMembershipStatus == 'suspended'
                        ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_assignmentStatus(row)),
                            const Text('Sin acceso · Membresía suspendida'),
                          ],
                        )
                        : Text(_assignmentStatus(row)),
                isThreeLine: row.assigneeMembershipStatus == 'suspended',
                trailing:
                    row.revokedAt == null
                        ? IconButton(
                          tooltip: 'Revocar asignación',
                          icon: const Icon(Icons.link_off),
                          onPressed:
                              () => _apply(
                                context,
                                ref,
                                (attempt) => ref
                                    .read(iamRepositoryProvider)
                                    .revokeCareAssignment(
                                      organizationId: organizationId,
                                      assignmentId: row.assignmentId!,
                                      attempt: attempt,
                                    ),
                              ),
                        )
                        : null,
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Asignar profesional'),
                onPressed:
                    () =>
                        _grant(context, ref, organizationId, episode, targets),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _memberName(CareAssignmentRecord row, List<EligibleMember> members) =>
    row.assigneeDisplayName ??
    members
        .where((member) => member.membershipId == row.membershipId)
        .map((member) => member.displayName)
        .firstOrNull ??
    'Profesional asignado';

String _assignmentStatus(CareAssignmentRecord row) {
  final timing = formatAssignmentTimeRange(
    validFrom: row.validFrom,
    validUntil: row.validUntil,
    revokedAt: row.revokedAt,
  );
  return timing;
}

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
    builder:
        (dialogContext) => StatefulBuilder(
          builder:
              (dialogContext, setState) => AlertDialog(
                title: const Text('Asignar profesional'),
                content: DropdownButtonFormField<String>(
                  value: selected,
                  items: [
                    for (final member in members)
                      DropdownMenuItem(
                        value: member.membershipId,
                        child: Text(member.displayName),
                      ),
                  ],
                  onChanged:
                      (value) => setState(() => selected = value ?? selected),
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
