import { createClient } from "@supabase/supabase-js";
import type { Database } from "../database.types.ts";
import { createAttachmentHandler } from "./handler.ts";

const url = Deno.env.get("SUPABASE_URL")!;
const key = Deno.env.get("SUPABASE_ANON_KEY")!;
const baseUrl = Deno.env.get("FHIR_SERVER_BASE_URL")!;
const handler = createAttachmentHandler({
  baseUrl,
  async authenticate(authorization) {
    const client = createClient<Database>(url, key, {
      global: { headers: { Authorization: authorization } },
    });
    const token = authorization.replace(/^Bearer\s+/i, "");
    const { data, error } = await client.auth.getUser(token);
    return !error && !!data.user;
  },
  async writeContext(org, hospitalization, authorization) {
    // Called as the user: RLS and the RPC decide, never the service role.
    const client = createClient<Database>(url, key, {
      global: { headers: { Authorization: authorization } },
    });
    const { data, error } = await client.rpc(
      "fhir_authorized_encounter_write_context",
      { p_organization_id: org, p_hospitalization_id: hospitalization },
    );
    if (error || !data?.[0]) return null;
    return data[0];
  },
});
Deno.serve(handler);
