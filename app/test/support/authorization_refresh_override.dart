import 'package:carer_record_app/app/session/authorization_refresh_coordinator.dart';
import 'package:carer_record_app/core/session/authorization_refresh.dart';

final authorizationRefreshOverride = authorizationRefreshProvider.overrideWith(
  authorizationRefreshFor,
);
