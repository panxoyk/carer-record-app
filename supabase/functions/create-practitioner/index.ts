import { createClient } from "@supabase/supabase-js";

import type { Database } from "../database.types.ts";

type PractitionerRole = Database["public"]["Enums"]["practitioner_role"];

const practitionerRoles = [
  "administrator",
  "physician",
  "nurse",
  "technician",
] as const satisfies readonly PractitionerRole[];

const response = (error: string, status: number) =>
  Response.json({ error }, { status });

const isPractitionerRole = (value: unknown): value is PractitionerRole =>
  typeof value === "string" &&
  practitionerRoles.includes(value as PractitionerRole);

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return response("method_not_allowed", 405);
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization) return response("unauthorized", 401);

  const callerClient = createClient<Database>(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authorization } } },
  );
  const { data: authData, error: authError } = await callerClient.auth
    .getUser();
  if (authError || !authData.user) return response("unauthorized", 401);

  const { data: caller } = await callerClient
    .from("practitioners")
    .select("role,status")
    .eq("id", authData.user.id)
    .maybeSingle();
  if (caller?.role !== "administrator" || caller.status !== "active") {
    return response("forbidden", 403);
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return response("invalid_payload", 400);
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return response("invalid_payload", 400);
  }

  const { email, password, displayName, role, licenseNumber } = body as Record<
    string,
    unknown
  >;
  if (
    typeof email !== "string" ||
    !email.trim() ||
    typeof password !== "string" ||
    !password ||
    typeof displayName !== "string" ||
    !displayName.trim() ||
    !isPractitionerRole(role) ||
    (licenseNumber != null && typeof licenseNumber !== "string")
  ) {
    return response("invalid_payload", 400);
  }

  // This client is intentionally separate so caller credentials never gain
  // Service Role privileges.
  const adminClient = createClient<Database>(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data: created, error: createError } = await adminClient.auth.admin
    .createUser({
      email: email.trim(),
      password,
      email_confirm: true,
    });
  if (createError || !created.user) return response("creation_failed", 400);

  const { error: profileError } = await adminClient.from("practitioners")
    .insert({
      id: created.user.id,
      display_name: displayName.trim(),
      role,
      license_number: licenseNumber?.trim() || null,
      status: "active",
    });
  if (profileError) {
    const { error: rollbackError } = await adminClient.auth.admin.deleteUser(
      created.user.id,
    );
    if (rollbackError) console.error("practitioner_create_rollback_failed");
    return response("creation_failed", 500);
  }

  return Response.json({ id: created.user.id }, { status: 201 });
});
