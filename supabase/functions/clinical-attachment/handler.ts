import type { Context } from "../clinical-record/handler.ts";
import {
  base64Size,
  matchesImageSignature,
  MAX_PHOTO_BYTES,
  PHOTO_TYPES,
  photoTransaction,
} from "../clinical-record/attachment.ts";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SOURCE = "685e5726-68ba-54c9-a528-bc7b7f6c20f8";
const FHIR_ID = /^[A-Za-z0-9.-]{1,64}$/;
const ALLOWED = [
  "clientEventId",
  "contentType",
  "dataBase64",
  "hospitalizationId",
  "organizationId",
  "takenAt",
];
/** 5 MB of image bytes as base64 plus the small JSON envelope. */
export const MAX_BODY_BYTES = Math.ceil(MAX_PHOTO_BYTES / 3) * 4 + 2048;
const INSTANT = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/;

/**
 * Attaches one clinical photo to an open, authorized encounter as a FHIR
 * `Binary` + `DocumentReference` (ADR-022). The app never talks to HAPI.
 */
export function createAttachmentHandler(deps: {
  authenticate(auth: string): Promise<boolean>;
  writeContext(
    org: string,
    hospitalization: string,
    auth: string,
  ): Promise<Context | null>;
  fetcher?: typeof fetch;
  baseUrl?: string;
  now?: () => Date;
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
    if (!authenticated) return json(401, { error: "unauthorized" });
    if (
      !/^application\/json(?:\s*;|$)/i.test(
        req.headers.get("content-type") ?? "",
      )
    ) return json(415, { error: "unsupported_media_type" });
    if (Number(req.headers.get("content-length") ?? 0) > MAX_BODY_BYTES) {
      return json(413, { error: "payload_too_large" });
    }
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
        if (size > MAX_BODY_BYTES) {
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
      input = JSON.parse(
        new TextDecoder("utf-8", { fatal: true }).decode(bytes),
      );
    } catch {
      return json(400, { error: "invalid_request" });
    }
    if (
      !input || typeof input !== "object" || Array.isArray(input) ||
      Object.keys(input).sort().join(",") !== ALLOWED.join(",")
    ) return json(400, { error: "invalid_request" });
    const {
      organizationId,
      hospitalizationId,
      clientEventId,
      contentType,
      dataBase64,
      takenAt,
    } = input;
    const now = (deps.now?.() ?? new Date()).getTime();
    if (
      typeof organizationId !== "string" || !UUID.test(organizationId) ||
      typeof hospitalizationId !== "string" || !UUID.test(hospitalizationId) ||
      typeof clientEventId !== "string" || !UUID.test(clientEventId) ||
      typeof takenAt !== "string" || !INSTANT.test(takenAt) ||
      !Number.isFinite(Date.parse(takenAt)) ||
      Date.parse(takenAt) > now + 5 * 60_000
    ) return json(400, { error: "invalid_request" });
    if (
      typeof contentType !== "string" ||
      !(PHOTO_TYPES as readonly string[]).includes(contentType) ||
      typeof dataBase64 !== "string"
    ) return json(415, { error: "unsupported_media_type" });
    const size = base64Size(dataBase64);
    if (size === null) return json(400, { error: "invalid_request" });
    if (size > MAX_PHOTO_BYTES) {
      return json(413, { error: "payload_too_large" });
    }
    if (!matchesImageSignature(contentType, dataBase64)) {
      return json(415, { error: "unsupported_media_type" });
    }
    let ctx: Context | null;
    try {
      ctx = await deps.writeContext(organizationId, hospitalizationId, auth);
    } catch {
      ctx = null;
    }
    if (
      !ctx || ctx.organization_id !== organizationId ||
      ctx.hospitalization_id !== hospitalizationId ||
      ctx.source_id !== SOURCE || !FHIR_ID.test(ctx.patient_fhir_id) ||
      !FHIR_ID.test(ctx.encounter_fhir_id)
    ) return json(404, { error: "not_found" });
    const baseUrl = deps.baseUrl ?? Deno.env.get("FHIR_SERVER_BASE_URL");
    let root: URL;
    try {
      const base = new URL(baseUrl ?? "");
      if (
        !["http:", "https:"].includes(base.protocol) || base.username ||
        base.password || base.search || base.hash
      ) return json(503, { error: "source_unavailable" });
      root = new URL(base.pathname.replace(/\/$/, ""), base.origin);
    } catch {
      return json(503, { error: "source_unavailable" });
    }
    try {
      const response = await (deps.fetcher ?? fetch)(root, {
        method: "POST",
        headers: {
          accept: "application/fhir+json",
          "content-type": "application/fhir+json",
        },
        redirect: "error",
        signal: AbortSignal.timeout(20_000),
        body: JSON.stringify(photoTransaction({
          ctx,
          clientEventId: clientEventId.toLowerCase(),
          contentType,
          dataBase64,
          takenAt,
        })),
      });
      if (!response.ok) return json(502, { error: "source_unavailable" });
      const bundle = await response.json();
      const location = bundle?.entry?.[1]?.response?.location;
      const id = /^DocumentReference\/([A-Za-z0-9.-]{1,64})(?:\/|$)/.exec(
        String(location ?? ""),
      )?.[1];
      if (!id) return json(502, { error: "source_unavailable" });
      return json(201, { id });
    } catch {
      return json(502, { error: "source_unavailable" });
    }
  };
}
