import 'package:supabase_flutter/supabase_flutter.dart';

/// Initializes the single Supabase client before repositories are constructed.
Future<void> initializeSupabase({
  required String url,
  required String publishableKey,
}) {
  if (url.isEmpty || publishableKey.isEmpty) {
    throw StateError(
      'SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY must be supplied with --dart-define.',
    );
  }
  return Supabase.initialize(url: url, publishableKey: publishableKey);
}

SupabaseClient get supabaseClient => Supabase.instance.client;
