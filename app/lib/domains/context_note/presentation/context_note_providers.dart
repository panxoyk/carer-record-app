import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/supabase_client.dart';
import '../data/context_note_repository.dart';
import '../data/draft_vault.dart';
import '../domain/dictation_audio.dart';
import '../data/plugin_dictation_audio.dart';

final contextNoteRepositoryProvider =
    Provider.autoDispose<ContextNoteRepository>(
      (ref) => ContextNoteRepository(ref.watch(supabaseClientProvider)),
    );

final draftVaultProvider = Provider.autoDispose<DraftVault>((ref) {
  final vault = DraftVault();
  // When this provider is first requested, opportunistically sweep expired
  // artifacts. Failures never block a milestone; the next purge retries.
  unawaited(vault.sweepExpired().catchError((Object _) => 0));
  return vault;
});

final dictationAudioFactoryProvider = Provider<DictationAudio Function()>(
  (ref) => PluginDictationAudio.new,
);
