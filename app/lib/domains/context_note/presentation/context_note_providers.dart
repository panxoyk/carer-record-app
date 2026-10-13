import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/supabase_client.dart';
import '../data/context_note_repository.dart';

final contextNoteRepositoryProvider =
    Provider.autoDispose<ContextNoteRepository>(
      (ref) => ContextNoteRepository(ref.watch(supabaseClientProvider)),
    );
