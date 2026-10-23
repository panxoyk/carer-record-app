import { loadClinicalRecord, type Purpose } from "./fhir.ts";

export type Context = {
  source_id: string;
  patient_fhir_id: string;
  encounter_fhir_id: string;
  organization_id: string;
  hospitalization_id: string;
  patient_id: string;
};
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SOURCE = "685e5726-68ba-54c9-a528-bc7b7f6c20f8";
const ALLOWED = new Set(["organizationId", "hospitalizationId", "purpose"]);
function sameContext(a: Context, b: Context): boolean {
  return a.source_id === b.source_id &&
    a.patient_fhir_id === b.patient_fhir_id &&
    a.encounter_fhir_id === b.encounter_fhir_id &&
    a.organization_id === b.organization_id &&
    a.hospitalization_id === b.hospitalization_id &&
    a.patient_id === b.patient_id;
}
export function createHandler(deps: {
  authenticate(auth: string): Promise<boolean>;
  context(
    org: string,
    hospitalization: string,
    purpose: string,
    auth: string,
  ): Promise<Context | null>;
  fetcher?: typeof fetch;
  baseUrl?: string;
}) {
  return async (req: Request): Promise<Response> => {
    const json = (status: number, body: unknown) =>
      new Response(JSON.stringify(body), {
        status,
        headers: {
          "content-type": "application/json",
          "cache-control": "no-store",
          "vary": "Authorization",
        },
      });
    if (req.method !== "POST") {
      return json(405, { error: "method_not_allowed" });
    }
    const auth = req.headers.get("authorization") ?? "";
    let authenticated = false;
    try {
      authenticated = /^Bearer\s+\S+$/i.test(auth) &&
        await deps.authenticate(auth);
    } catch {
      authenticated = false;
    }
    if (!authenticated) {
      return json(401, { error: "unauthorized" });
    }
    if (
      !/^application\/json(?:\s*;|$)/i.test(
        req.headers.get("content-type") ?? "",
      )
    ) return json(415, { error: "unsupported_media_type" });
    const length = Number(req.headers.get("content-length") ?? 0);
    if (length > 4096) return json(413, { error: "payload_too_large" });
    let input: Record<string, unknown>;
    try {
      if (!req.body) return json(400, { error: "invalid_request" });
      const reader = req.body.getReader();
      const chunks: Uint8Array[] = [];
      let size = 0;
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > 4096) {
          await reader.cancel();
          return json(413, { error: "payload_too_large" });
        }
        chunks.push(value);
      }
      const bytes = new Uint8Array(size);
      let offset = 0;
      for (const chunk of chunks) {
        bytes.set(chunk, offset);
        offset += chunk.byteLength;
      }
      const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
      input = JSON.parse(text);
    } catch {
      return json(400, { error: "invalid_request" });
    }
    if (
      !input || typeof input !== "object" || Array.isArray(input) ||
      Object.keys(input).some((k) => !ALLOWED.has(k))
    ) return json(400, { error: "invalid_request" });
    const org = input.organizationId,
      hospitalization = input.hospitalizationId,
      purpose = input.purpose ?? "record";
    if (
      typeof org !== "string" || !UUID.test(org) ||
      typeof hospitalization !== "string" || !UUID.test(hospitalization) ||
      typeof purpose !== "string" || !["record", "timeline"].includes(purpose)
    ) return json(400, { error: "invalid_request" });
    let ctx: Context | null;
    try {
      ctx = await deps.context(org, hospitalization, purpose, auth);
    } catch {
      return json(404, { error: "not_found" });
    }
    if (
      !ctx || ctx.organization_id !== org ||
      ctx.hospitalization_id !== hospitalization
    ) return json(404, { error: "not_found" });
    if (
      ctx.source_id !== SOURCE ||
      !/^[A-Za-z0-9.-]{1,64}$/.test(ctx.patient_fhir_id) ||
      !/^[A-Za-z0-9.-]{1,64}$/.test(ctx.encounter_fhir_id)
    ) return json(404, { error: "not_found" });
    const baseUrl = deps.baseUrl ?? Deno.env.get("FHIR_SERVER_BASE_URL");
    if (!baseUrl) return json(503, { error: "source_unavailable" });
    try {
      const parsed = new URL(baseUrl);
      if (
        !["http:", "https:"].includes(parsed.protocol) || !parsed.hostname ||
        parsed.username || parsed.password || parsed.search || parsed.hash
      ) return json(503, { error: "source_unavailable" });
    } catch {
      return json(503, { error: "source_unavailable" });
    }
    try {
      const result = await loadClinicalRecord(
        ctx,
        purpose as Purpose,
        deps.fetcher ?? fetch,
        baseUrl,
      );
      let again: Context | null;
      try {
        again = await deps.context(org, hospitalization, purpose, auth);
      } catch {
        again = null;
      }
      if (!again || !sameContext(again, ctx)) {
        return json(404, { error: "not_found" });
      }
      return json(200, result);
    } catch {
      return json(502, { error: "source_unavailable" });
    }
  };
}
