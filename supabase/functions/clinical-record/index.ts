import { createClient } from "@supabase/supabase-js";
import type { Database } from "../database.types.ts";
import { createHandler } from "./handler.ts";

const url = Deno.env.get("SUPABASE_URL")!;
const key = Deno.env.get("SUPABASE_ANON_KEY")!;
const baseUrl = Deno.env.get("FHIR_SERVER_BASE_URL")!;
const handler = createHandler({
  baseUrl,
  async authenticate(authorization) {
    const client = createClient<Database>(url, key, {
      global: { headers: { Authorization: authorization } },
    });
    const token = authorization.replace(/^Bearer\s+/i, "");
    const { data, error } = await client.auth.getUser(token);
    return !error && !!data.user;
  },
  async context(org, hospitalization, purpose, authorization) {
    const client = createClient<Database>(url, key, {
      global: { headers: { Authorization: authorization } },
    });
    const { data, error } = await client.rpc(
      "fhir_authorized_encounter_context",
      {
        p_organization_id: org,
        p_hospitalization_id: hospitalization,
        p_purpose: purpose,
      },
    );
    return error ? null : data?.[0] ?? null;
  },
});
Deno.serve(handler);
