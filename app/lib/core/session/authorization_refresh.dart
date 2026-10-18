import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef AuthorizationRefresh = void Function();

final authorizationRefreshProvider = Provider<AuthorizationRefresh>((ref) {
  throw StateError('Authorization refresh composition is missing.');
});
