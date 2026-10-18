import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/authorization_refresh.dart';
import '../../domains/clinical_event/presentation/clinical_event_providers.dart';
import '../../domains/institutional/presentation/iam_providers.dart';
import '../../domains/patient/presentation/patient_providers.dart';

void invalidateAuthorizationAndData(Ref ref) {
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

AuthorizationRefresh authorizationRefreshFor(Ref ref) =>
    () => invalidateAuthorizationAndData(ref);
