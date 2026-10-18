import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/clinical_toast.dart';
import '../../core/session/authorization_refresh.dart';
import '../../domains/auth/presentation/auth_providers.dart';
import '../../domains/institutional/presentation/iam_providers.dart';

class AuthorizationLifecycleBoundary extends ConsumerStatefulWidget {
  const AuthorizationLifecycleBoundary({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<AuthorizationLifecycleBoundary> createState() =>
      _AuthorizationLifecycleBoundaryState();
}

class _AuthorizationLifecycleBoundaryState
    extends ConsumerState<AuthorizationLifecycleBoundary>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    _identity = ref.read(authGateProvider).session?.user.id;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(authorizationRefreshProvider)();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String? _identity;
  @override
  Widget build(BuildContext context) {
    ref.listen(authGateProvider, (_, gate) {
      final key = gate.session?.user.id;
      if (key != _identity) {
        _identity = key;
        ClinicalToast.dismissAll();
      }
    });
    ref.listen(selectedOrganizationProvider, (previous, next) {
      if (previous?.userId != next?.userId ||
          previous?.organizationId != next?.organizationId) {
        ClinicalToast.dismissAll();
      }
    });
    return widget.child;
  }
}
