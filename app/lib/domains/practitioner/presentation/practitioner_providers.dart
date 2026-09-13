import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/supabase_client.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/practitioner_repository.dart';
import '../domain/entities/practitioner.dart';

final practitionerRepositoryProvider = Provider<PractitionerRepository>(
  (ref) => PractitionerRepository(ref.watch(supabaseClientProvider)),
);

final practitionersProvider = FutureProvider<List<Practitioner>>(
  (ref) => ref.watch(practitionerRepositoryProvider).list(),
);

final currentPractitionerProvider = FutureProvider<Practitioner?>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return null;
  return ref.watch(practitionerRepositoryProvider).findById(session.user.id);
});

final currentRoleProvider = Provider<AsyncValue<PractitionerRole?>>(
  (ref) => ref.watch(currentPractitionerProvider).whenData((p) => p?.role),
);
