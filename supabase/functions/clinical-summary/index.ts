import { createClient } from 'npm:@supabase/supabase-js@2';

Deno.serve(async (request) => {
  const authorization = request.headers.get('Authorization');
  if (!authorization) return Response.json({ error: 'Unauthorized' }, { status: 401 });

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    { global: { headers: { Authorization: authorization } } },
  );
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return Response.json({ error: 'Unauthorized' }, { status: 401 });

  // AI provider integration intentionally deferred; this is the protected boundary.
  return Response.json({ status: 'not_implemented', requestedBy: user.id }, { status: 501 });
});
