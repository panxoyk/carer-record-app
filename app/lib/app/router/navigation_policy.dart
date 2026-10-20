import '../../domains/institutional/domain/iam_entities.dart';

/// Returns the redirect needed for optional local model setup, or null when
/// the auth/authorization redirect should decide the destination.
String? modelSetupRedirect({
  required String location,
  required bool modelsReady,
  required bool skipped,
  bool setupAwaitingContinue = false,
  required bool hasSession,
  bool recoveringPassword = false,
}) {
  if (recoveringPassword) {
    return location == '/update-password' ? null : '/update-password';
  }
  if (location == '/recover' || location == '/update-password') return null;
  if (location == '/models' && !hasSession) return '/login';
  // Authenticated users may manage installed models even when cleanup leaves
  // one unavailable; authorization checks still run below this setup gate.
  if (location == '/models' && hasSession) return null;
  if (!modelsReady && !skipped && location != '/setup') return '/setup';
  if (skipped && location == '/setup' && !hasSession) return '/login';
  if (modelsReady &&
      location == '/setup' &&
      !setupAwaitingContinue &&
      !hasSession) {
    return '/login';
  }
  return null;
}

String? permissionRedirectForLocation(IamContext context, String location) {
  if (location == '/') {
    if (context.allows('clinical.census.read') &&
        context.allows('clinical.patient.read')) {
      return '/patients';
    }
    return '/settings';
  }
  if (location == '/users' && !context.allows('iam.membership.read')) {
    return '/settings';
  }
  if (location == '/assignments' &&
      !context.allows('clinical.assignment.manage')) {
    return '/settings';
  }
  if (location == '/roles' &&
      (!context.allows('iam.role.read') ||
          !context.allows('iam.role.manage'))) {
    return '/settings';
  }
  if (location.startsWith('/patients') &&
      (!context.allows('clinical.census.read') ||
          !context.allows('clinical.patient.read'))) {
    return '/settings';
  }
  if (location.startsWith('/hospitalizations/') &&
      (!context.allows('clinical.census.read') ||
          !context.allows('clinical.patient.read'))) {
    return '/settings';
  }
  if (location.startsWith('/hospitalizations/') &&
      !location.endsWith('/details') &&
      !context.allows('clinical.timeline.read')) {
    return '/settings';
  }
  if (location.startsWith('/fhir/') &&
      (!context.allows('clinical.census.read') ||
          !context.allows('clinical.patient.read'))) {
    return '/settings';
  }
  return null;
}

IamContext? contextForOrganizationSelection(
  List<IamContext> contexts,
  OrganizationSelection? selection,
  String sessionUserId,
) => IamContext.selectForSession(contexts, selection, sessionUserId);

String? organizationSelectionRedirect(
  List<IamContext> contexts,
  OrganizationSelection? selection,
  String sessionUserId,
  String location,
) {
  final selected = contextForOrganizationSelection(
    contexts,
    selection,
    sessionUserId,
  );
  if (contexts.length > 1 && selected == null) {
    return location == '/select-organization' ? null : '/select-organization';
  }
  if (contexts.length > 1 && location == '/select-organization') return '/';
  return null;
}
