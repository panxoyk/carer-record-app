import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/clinical_toast.dart';
import '../../../core/session/session_artifact_cleanup.dart';
import 'auth_providers.dart';

final signOutBusyProvider = StateProvider<bool>((ref) => false);

Future<void> signOutAction(BuildContext context, WidgetRef ref) async {
  final busy = ref.read(signOutBusyProvider.notifier);
  if (ref.read(signOutBusyProvider)) return;
  final cleanupArtifacts = ref.read(sessionArtifactCleanupProvider);
  busy.state = true;
  Object? authError;
  Object? cleanupError;
  try {
    await ref.read(authRepositoryProvider).signOut();
    ClinicalToast.dismissAll();
  } catch (error) {
    authError = error;
  }
  try {
    await cleanupArtifacts();
  } catch (error) {
    cleanupError = error;
  }
  try {
    if (authError != null) {
      if (context.mounted) {
        ClinicalToast.failure(
          context,
          identifier: 'sign-out-failure',
          message: 'No fue posible cerrar sesión.',
        );
      }
    } else if (cleanupError != null && context.mounted) {
      ClinicalToast.failure(
        context,
        identifier: 'sign-out-cleanup-failure',
        message: 'La sesión se cerró, pero no se pudieron eliminar todos los borradores locales.',
        withDetails: true,
      );
    }
  } finally {
    busy.state = false;
  }
}
