import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/supabase_client.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../patient/presentation/patient_providers.dart';
import '../../clinical_event/presentation/clinical_event_providers.dart';
import '../data/iam_models.dart';
import '../data/iam_repository.dart';

final iamRepositoryProvider = Provider.autoDispose<IamRepository>(
  (ref) => IamRepository(ref.watch(supabaseClientProvider)),
);

final AutoDisposeFutureProvider<List<IamContext>> iamContextsProvider =
    FutureProvider.autoDispose<List<IamContext>>((ref) async {
      if (ref.watch(sessionProvider) == null) return const [];
      try {
        return await ref.watch(iamRepositoryProvider).currentContexts();
      } on FormatException {
        return const [];
      }
    });

final Provider<String?> currentSessionUserIdProvider = Provider(
  (ref) => ref.watch(sessionProvider)?.user.id,
);

final StateNotifierProvider<
  OrganizationSelectionController,
  OrganizationSelection?
>
selectedOrganizationProvider =
    StateNotifierProvider<
      OrganizationSelectionController,
      OrganizationSelection?
    >((ref) {
      return OrganizationSelectionController(
        ref.watch(currentSessionUserIdProvider),
      );
    });

class OrganizationSelectionController
    extends StateNotifier<OrganizationSelection?> {
  OrganizationSelectionController(this._userId) : super(null);

  final String? _userId;

  void select(String organizationId) {
    final userId = _userId;
    if (userId == null) return;
    state = OrganizationSelection(
      userId: userId,
      organizationId: organizationId,
    );
  }
}

final AutoDisposeFutureProvider<IamContext?> iamContextProvider =
    FutureProvider.autoDispose<IamContext?>((ref) async {
      final contexts = await ref.watch(iamContextsProvider.future);
      final selected = ref.watch(selectedOrganizationProvider);
      final session = ref.watch(sessionProvider);
      if (session == null) return null;
      return IamContext.selectForSession(contexts, selected, session.user.id);
    });

final AutoDisposeFutureProvider<List<IamMember>> iamMembersProvider =
    FutureProvider.autoDispose<List<IamMember>>((ref) async {
      final contextFuture = ref.watch(iamContextProvider.future);
      final repository = ref.watch(iamRepositoryProvider);
      final context = await contextFuture;
      if (context == null || !context.allows('iam.membership.read')) {
        return const [];
      }
      return repository.members(context.organizationId);
    });

final AutoDisposeFutureProvider<List<IamRole>> iamRolesProvider =
    FutureProvider.autoDispose<List<IamRole>>((ref) async {
      final contextFuture = ref.watch(iamContextProvider.future);
      final repository = ref.watch(iamRepositoryProvider);
      final context = await contextFuture;
      if (context == null || !context.allows('iam.role.read')) {
        return const [];
      }
      return repository.roles(context.organizationId);
    });

final AutoDisposeFutureProvider<List<IamPermission>>
iamDelegablePermissionsProvider = FutureProvider.autoDispose((ref) async {
  if (ref.watch(sessionProvider) == null) return const [];
  final context = await ref.watch(iamContextProvider.future);
  if (context == null ||
      !context.allows('iam.role.read') ||
      !context.allows('iam.role.manage')) {
    return const [];
  }
  final permissions = await ref
      .watch(iamRepositoryProvider)
      .delegablePermissions();
  return permissions
      .where((permission) => context.allows(permission.code))
      .toList();
});

final AutoDisposeFutureProvider<Map<String, List<IamRoleAssignment>>>
iamRoleAssignmentsProvider =
    FutureProvider.autoDispose<Map<String, List<IamRoleAssignment>>>((
      ref,
    ) async {
      final contextFuture = ref.watch(iamContextProvider.future);
      final repository = ref.watch(iamRepositoryProvider);
      final context = await contextFuture;
      if (context == null || !context.allows('iam.membership.read')) {
        return <String, List<IamRoleAssignment>>{};
      }
      return repository.roleAssignments(context.organizationId);
    });

final AutoDisposeFutureProvider<List<CareAssignmentRecord>>
careAssignmentsProvider =
    FutureProvider.autoDispose<List<CareAssignmentRecord>>((ref) async {
      final contextFuture = ref.watch(iamContextProvider.future);
      final repository = ref.watch(iamRepositoryProvider);
      final context = await contextFuture;
      if (context == null || !context.allows('clinical.assignment.manage')) {
        return const [];
      }
      return repository.assignments(context.organizationId);
    });

final AutoDisposeFutureProvider<Map<String, String>>
careAssignmentPatientNamesProvider =
    FutureProvider.autoDispose<Map<String, String>>((ref) async {
      final context = await ref.watch(iamContextProvider.future);
      if (context == null ||
          !context.allows('clinical.assignment.manage') ||
          !context.allows('clinical.census.read') ||
          !context.allows('clinical.patient.read')) {
        return const {};
      }
      return ref
          .watch(iamRepositoryProvider)
          .censusPatientNames(context.organizationId);
    });

final AutoDisposeFutureProvider<List<EligibleMember>> eligibleMembersProvider =
    FutureProvider.autoDispose<List<EligibleMember>>((ref) async {
      final contextFuture = ref.watch(iamContextProvider.future);
      final repository = ref.watch(iamRepositoryProvider);
      final context = await contextFuture;
      if (context == null || !context.allows('clinical.assignment.manage')) {
        return const [];
      }
      return repository.eligibleMembers(context.organizationId);
    });

void invalidateAuthorizationAndData(WidgetRef ref) {
  // The SQL context is authoritative; invalidate its source before all dependents.
  ref.invalidate(iamContextsProvider);
  ref.invalidate(iamContextProvider);
  ref.invalidate(iamMembersProvider);
  ref.invalidate(iamRolesProvider);
  ref.invalidate(iamDelegablePermissionsProvider);
  ref.invalidate(iamRoleAssignmentsProvider);
  ref.invalidate(careAssignmentsProvider);
  ref.invalidate(careAssignmentPatientNamesProvider);
  ref.invalidate(eligibleMembersProvider);
  ref.invalidate(patientsProvider);
  ref.invalidate(patientProvider);
  ref.invalidate(hospitalizationClinicalEventsProvider);
}
