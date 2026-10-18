import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/authorization_refresh.dart';

class AdministrativeEntryRefresh extends ConsumerStatefulWidget {
  const AdministrativeEntryRefresh({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<AdministrativeEntryRefresh> createState() =>
      _AdministrativeEntryRefreshState();
}

class ClinicalEntryRefresh extends ConsumerStatefulWidget {
  const ClinicalEntryRefresh({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<ClinicalEntryRefresh> createState() =>
      _ClinicalEntryRefreshState();
}

class _ClinicalEntryRefreshState extends ConsumerState<ClinicalEntryRefresh> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(authorizationRefreshProvider)();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Widget administrativeEntryForLocation(String location, Widget child) {
  if (location != '/users' &&
      location != '/assignments' &&
      location != '/roles') {
    throw ArgumentError.value(
      location,
      'location',
      'Not an administrative route',
    );
  }
  return AdministrativeEntryRefresh(child: child);
}

class _AdministrativeEntryRefreshState
    extends ConsumerState<AdministrativeEntryRefresh> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(authorizationRefreshProvider)();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
