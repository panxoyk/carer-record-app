import type { Context } from "./handler.ts";
import { PHOTO_CATEGORY } from "./fhir.ts";

/** Base64 of at most 5 MB of image bytes (ADR-024). */
export const MAX_PHOTO_BYTES = 5_000_000;
const MAX_RESPONSE_BYTES = 8_000_000;
const TIMEOUT_MS = 10_000;
const ID = /^[A-Za-z0-9.-]{1,64}$/;
export const PHOTO_TYPES = ["image/jpeg", "image/png"] as const;
// deno-lint-ignore no-explicit-any
type Resource = Record<string, any>;

export type Attachment = { contentType: string; dataBase64: string };

function sourceRoot(baseURL: string): URL {
  const base = new URL(baseURL);
  if (
    !["http:", "https:"].includes(base.protocol) || base.username ||
    base.password || base.search || base.hash
  ) throw new Error("invalid source base URL");
  return new URL(`${base.pathname.replace(/\/$/, "")}/`, base.origin);
}

async function readJson(response: Response): Promise<Resource> {
  if (!response.ok) throw new Error("FHIR upstream error");
  if (!response.body) throw new Error("FHIR response body missing");
  const reader = response.body.getReader();
  const decoder = new TextDecoder("utf-8", { fatal: true });
  let size = 0, text = "";
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > MAX_RESPONSE_BYTES) {
      await reader.cancel();
      throw new Error("FHIR byte limit exceeded");
    }
    text += decoder.decode(value, { stream: true });
  }
  return JSON.parse(text + decoder.decode()) as Resource;
}

/** Decoded byte length of a base64 string, or null when it is malformed. */
export function base64Size(data: string): number | null {
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(data) || data.length % 4 !== 0) {
    return null;
  }
  const padding = data.endsWith("==") ? 2 : data.endsWith("=") ? 1 : 0;
  return data.length / 4 * 3 - padding;
}

export function isPhotoDocumentFor(r: Resource, ctx: Context): boolean {
  const subject = r.subject?.reference;
  const encounter = r.context?.encounter?.[0]?.reference;
  const category = (r.category ?? []).some((c: Resource) =>
    c.coding?.some((x: Resource) => x.code === PHOTO_CATEGORY)
  );
  return r.resourceType === "DocumentReference" &&
    subject === `Patient/${ctx.patient_fhir_id}` &&
    encounter === `Encounter/${ctx.encounter_fhir_id}` && category;
}

/**
 * Loads one clinical photo of the authorized encounter. The image lives in a
 * `Binary` referenced by `DocumentReference.content[0].attachment.url`.
 */
export async function loadAttachment(
  ctx: Context,
  documentId: string,
  fetcher: typeof fetch,
  baseURL: string,
): Promise<Attachment> {
  if (!ID.test(documentId)) throw new Error("invalid document id");
  const root = sourceRoot(baseURL);
  const get = async (path: string) =>
    readJson(
      await fetcher(new URL(path, root), {
        headers: { accept: "application/fhir+json" },
        redirect: "error",
        signal: AbortSignal.timeout(TIMEOUT_MS),
      }),
    );
  const document = await get(`DocumentReference/${documentId}`);
  if (document.id !== documentId || !isPhotoDocumentFor(document, ctx)) {
    throw new Error("photo outside the authorized encounter");
  }
  const attachment = document.content?.[0]?.attachment ?? {};
  let contentType: unknown = attachment.contentType;
  let data: unknown = attachment.data;
  if (data == null) {
    const binaryId = /^Binary\/([A-Za-z0-9.-]{1,64})$/.exec(
      String(attachment.url ?? ""),
    )?.[1];
    if (!binaryId) throw new Error("photo without binary");
    const binary = await get(`Binary/${binaryId}`);
    if (binary.resourceType !== "Binary" || binary.id !== binaryId) {
      throw new Error("invalid photo binary");
    }
    contentType = binary.contentType;
    data = binary.data;
  }
  if (
    typeof contentType !== "string" ||
    !(PHOTO_TYPES as readonly string[]).includes(contentType) ||
    typeof data !== "string"
  ) throw new Error("unsupported photo");
  const size = base64Size(data);
  if (size === null || size > MAX_PHOTO_BYTES) throw new Error("invalid photo");
  return { contentType, dataBase64: data };
}
