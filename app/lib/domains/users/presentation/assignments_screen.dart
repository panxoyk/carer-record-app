import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/clinical_design_system.dart';
import '../../../core/design_system/clinical_toast.dart';
import '../../../core/design_system/anchored_selector.dart';
import '../../../core/time/clinical_time.dart';
import '../../institutional/domain/iam_entities.dart';
import '../../institutional/presentation/iam_providers.dart';
import '../../../core/session/authorization_refresh.dart';
import 'controllers/care_assignments_controller.dart';

typedef _ControllerForOrganization = CareAssignmentsController Function();
typedef _PresentAssignmentOutcome = Future<void> Function(
  Future<AdminOperationResult?> operation,
  CareAssignmentsController controller,
  String successMessage,
);

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
  CareAssignmentsController? _controller;
  String? _controllerScope;

  CareAssignmentsController _controllerFor(
    String organizationId,
    String profileId,
  ) {
    final scope = '$organizationId:$profileId';
    if (_controllerScope != scope) {
      _controller?.dispose();
      _controller = CareAssignmentsController(
        administration: ref.read(careAssignmentAdministrationProvider),
        attemptFactory: ref.read(iamOperationAttemptFactoryProvider),
        refreshAuthorization: ref.read(authorizationRefreshProvider),
        organizationId: organizationId,
      );
      _controllerScope = scope;
    }
    return _controller!;
  }

  @override
  void dispose() {
    _controller?.dispose();
    _patientSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iamState = ref.watch(iamContextProvider);
    final iam = iamState.valueOrNull;
    final currentScope = iam == null
        ? null
        : '${iam.organizationId}:${iam.profileId}';
    if (_controller != null && _controllerScope != currentScope) {
      _controller!.dispose();
      _controller = null;
      _controllerScope = null;
    }
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
                      controllerFor: () =>
                          _controllerFor(iam!.organizationId, iam.profileId),
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
    required this.controllerFor,
  });
  final List<CareAssignmentRecord> items;
  final List<EligibleMember> members;
  final Map<String, String> patientNames;
  final String patientQuery;
  final _ControllerForOrganization controllerFor;

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
            key: ValueKey(
              '${iam.organizationId}:${iam.profileId}:${entry.key}',
            ),
            hospitalizationId: entry.key,
            rows: entry.value,
            members: members,
            patientName: patientNames[entry.key],
            organizationId: iam.organizationId,
            controllerFor: controllerFor,
          ),
        if (items.isEmpty || visibleEpisodes.isEmpty)
          const ListTile(title: Text('No hay hospitalizaciones disponibles.')),
      ],
    );
  }
}

class _HospitalizationCard extends ConsumerStatefulWidget {
  const _HospitalizationCard({
    super.key,
    required this.hospitalizationId,
    required this.rows,
    required this.members,
    required this.patientName,
    required this.organizationId,
    required this.controllerFor,
  });
  final String hospitalizationId;
  final List<CareAssignmentRecord> rows;
  final List<EligibleMember> members;
  final String? patientName;
  final String organizationId;
  final _ControllerForOrganization controllerFor;

  @override
  ConsumerState<_HospitalizationCard> createState() =>
      _HospitalizationCardState();
}

class _HospitalizationCardState extends ConsumerState<_HospitalizationCard> {
  CareAssignmentSnapshot? _failedSnapshot;
  String? _operationError;
  bool _busy = false;

  @override
  void didUpdateWidget(covariant _HospitalizationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.organizationId != widget.organizationId ||
        oldWidget.hospitalizationId != widget.hospitalizationId) {
      _failedSnapshot = null;
      _operationError = null;
      return;
    }
    final snapshot = _failedSnapshot;
    if (snapshot?.action == CareAssignmentAction.revoke &&
        !widget.rows.any((row) => row.assignmentId == snapshot!.targetId)) {
      _failedSnapshot = null;
      _operationError = null;
    }
  }

  Future<void> _run(
    Future<AdminOperationResult?> operation,
    CareAssignmentsController controller,
    String successMessage,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _operationError = null;
    });
    AdminOperationResult? result;
    try {
      result = await operation;
    } catch (_) {
      if (mounted) {
        setState(() {
          _failedSnapshot = controller.retrySnapshot;
          _operationError = 'No se pudo confirmar la operación. El resultado podría haberse aplicado; reintenta para verificarlo.';
        });
        ClinicalToast.failure(
          context,
          message: _careFailureMessage(controller.retrySnapshot),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
    if (!mounted || result == null) return;
    if (result.success) {
      setState(() {
        _failedSnapshot = null;
        _operationError = null;
      });
      ClinicalToast.success(context, message: successMessage);
    } else {
      setState(() {
        _failedSnapshot = null;
        _operationError = _careResultMessage(result!.code);
      });
      ClinicalToast.failure(
        context,
        message: _careFailureMessage(controller.retrySnapshot),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hospitalizationId = widget.hospitalizationId;
    final rows = widget.rows;
    final members = widget.members;
    final patientName = widget.patientName;
    final organizationId = widget.organizationId;
    final controllerFor = widget.controllerFor;
    final episode = rows.first;
    final now = DateTime.now().toUtc();
    final activeMemberships = rows
        .where(
          (row) =>
              row.assignmentId != null &&
              row.membershipId != null &&
              row.revokedAt == null &&
              (row.validFrom == null || !row.validFrom!.toUtc().isAfter(now)) &&
              (row.validUntil == null || row.validUntil!.toUtc().isAfter(now)),
        )
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
          if (first != null) {
            return 1;
          }
          if (second != null) {
            return -1;
          }
        } else {
          final byDate = first.compareTo(second);
          if (byDate != 0) return byDate;
        }
        return a.assignmentId!.compareTo(b.assignmentId!);
      });
    }
    final retry = _failedSnapshot;
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
                  onPressed: () async {
                    try {
                      await Clipboard.setData(
                        ClipboardData(text: hospitalizationId),
                      );
                      if (context.mounted) {
                        ClinicalToast.success(
                          context,
                          message: 'Identificador copiado.',
                        );
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ClinicalToast.failure(
                          context,
                          message: 'No pudimos copiar el identificador.',
                        );
                      }
                    }
                  },
                ),
              ],
            ),
            if (_operationError != null) ...[
              Text(
                _operationError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              if (retry != null)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          controllerFor().retry(retry),
                          controllerFor(),
                          _careSuccess(retry.action),
                        ),
                  child: const Text('Reintentar operación'),
                ),
            ],
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
                  controllerFor: controllerFor,
                  now: now,
                  presentOutcome: (operation, controller, message) =>
                      _run(operation, controller, message),
                ),
              ],
            ],
            const SizedBox(height: ClinicalSpacing.section),
            OutlinedButton.icon(
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Asignar profesional'),
              onPressed: _busy
                  ? null
                  : () => _grant(
                      context,
                      controllerFor,
                      episode,
                      targets,
                      (operation, controller, message) =>
                          _run(operation, controller, message),
                    ),
            ),
            if (targets.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: ClinicalSpacing.compact),
                child: Text('No hay profesionales elegibles.'),
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
    required this.controllerFor,
    required this.presentOutcome,
  });

  final List<CareAssignmentRecord> history;
  final List<EligibleMember> members;
  final String organizationId;
  final DateTime now;
  final _ControllerForOrganization controllerFor;
  final _PresentAssignmentOutcome presentOutcome;

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
              _revokeButton(
                context,
                controllerFor,
                organizationId,
                revocable,
                name,
                presentOutcome,
              ),
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
  _ControllerForOrganization controllerFor,
  String organizationId,
  List<CareAssignmentRecord> revocable,
  String name,
  _PresentAssignmentOutcome presentOutcome,
) => IconButton(
  tooltip: 'Quitar acceso',
  icon: const Icon(Icons.person_remove_outlined),
  style: IconButton.styleFrom(foregroundColor: ClinicalColors.destructive),
  onPressed: () => _confirmRevoke(
    context,
    controllerFor,
    organizationId,
    revocable,
    name,
    presentOutcome,
  ),
);

Future<void> _confirmRevoke(
  BuildContext context,
  _ControllerForOrganization controllerFor,
  String organizationId,
  List<CareAssignmentRecord> revocable,
  String name,
  _PresentAssignmentOutcome presentOutcome,
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
  final controller = controllerFor();
  await presentOutcome(
    controller.revoke(assignmentId: row.assignmentId!),
    controller,
    'Acceso a la hospitalización revocado.',
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
  _ControllerForOrganization controllerFor,
  CareAssignmentRecord hospitalization,
  List<EligibleMember> members,
  _PresentAssignmentOutcome presentOutcome,
) async {
  if (members.isEmpty) {
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
  final controller = controllerFor();
  await presentOutcome(
    controller.grant(
      hospitalizationId: hospitalization.hospitalizationId,
      membershipId: selected,
    ),
    controller,
    'Profesional asignado a la hospitalización.',
  );
}

String _careSuccess(CareAssignmentAction action) => switch (action) {
  CareAssignmentAction.grant => 'Profesional asignado a la hospitalización.',
  CareAssignmentAction.revoke => 'Acceso a la hospitalización revocado.',
};

String _careFailureMessage(
  CareAssignmentSnapshot? snapshot,
) => switch (snapshot?.action) {
  CareAssignmentAction.grant =>
    'No se pudo confirmar la asignación del profesional a la hospitalización.',
  CareAssignmentAction.revoke =>
    'No se pudo confirmar la revocación del acceso a la hospitalización.',
  null => 'No se pudo confirmar la operación de asignación.',
};

String _careResultMessage(String code) => switch (code) {
  'denied' => 'No tienes autorización vigente para gestionar esta asignación.',
  'idempotency_conflict' => 'La solicitud no coincide con el intento anterior. Recarga antes de continuar.',
  _ => 'No fue posible completar la asignación solicitada.',
};
