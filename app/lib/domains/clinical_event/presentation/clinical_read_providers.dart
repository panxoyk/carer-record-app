import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/supabase_client.dart';
import '../data/clinical_read_client.dart';

final clinicalReadClientProvider = Provider.autoDispose<ClinicalReadClient>(
  (ref) => SupabaseClinicalReadClient(ref.watch(supabaseClientProvider)),
);
