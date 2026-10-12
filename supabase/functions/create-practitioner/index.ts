import { createClient } from "@supabase/supabase-js";
import type { Database } from "../database.types.ts";
import { createHandler } from "./handler.ts";

const url = Deno.env.get("SUPABASE_URL")!;
const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const handler = createHandler({
  async authenticate(authorization) {
    const caller = createClient<Database>(url, anonKey, {
      global: { headers: { Authorization: authorization } },
    });
    const token = authorization.replace(/^Bearer\s+/i, "");
    const { data, error } = await caller.auth.getUser(token);
    return error || !data.user ? null : { id: data.user.id };
  },
  async preflight(input, authorization) {
    const caller = createClient<Database>(url, anonKey, {
      global: { headers: { Authorization: authorization } },
    });
    const { data, error } = await caller.rpc(
      "preflight_organization_member_registration",
      {
        p_organization_id: input.organizationId,
        p_email: input.email,
        p_display_name: input.displayName,
        p_role_id: input.roleId,
        p_idempotency_key: input.idempotencyKey,
      },
    );
    return error ? null : data?.[0] ?? null;
  },
  async createAuthUser(email, password) {
    const admin = createClient<Database>(url, serviceRoleKey);
    const { data, error } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
    return error || !data.user ? null : data.user.id;
  },
  async register(input, authUserId, authorization) {
    const caller = createClient<Database>(url, anonKey, {
      global: { headers: { Authorization: authorization } },
    });
    const { data, error } = await caller.rpc("register_organization_member", {
      p_organization_id: input.organizationId,
      p_auth_user_id: authUserId,
      p_email: input.email,
      p_display_name: input.displayName,
      p_role_id: input.roleId,
      p_idempotency_key: input.idempotencyKey,
    });
    return error ? null : data?.[0] ?? null;
  },
  async deleteAuthUser(id) {
    const admin = createClient<Database>(url, serviceRoleKey);
    const { error } = await admin.auth.admin.deleteUser(id);
    return !error;
  },
});

Deno.serve(handler);
