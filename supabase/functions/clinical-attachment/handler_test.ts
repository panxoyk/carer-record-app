import { createAttachmentHandler } from "./handler.ts";
import type { Context } from "../clinical-record/handler.ts";
import { loadAttachment } from "../clinical-record/attachment.ts";

const assert = (ok: unknown, message: string) => {
  if (!ok) throw new Error(message);
};
const ORG = "11111111-1111-4111-8111-111111111111";
const EPISODE = "22222222-2222-4222-8222-222222222222";
const NOTE = "33333333-3333-4333-8333-333333333333";
const ctx: Context = {
  source_id: "685e5726-68ba-54c9-a528-bc7b7f6c20f8",
  patient_fhir_id: "p1",
  encounter_fhir_id: "e1",
  organization_id: ORG,
  hospitalization_id: EPISODE,
  patient_id: "44444444-4444-4444-8444-444444444444",
};
// Smallest JPEG/PNG headers followed by padding bytes.
const jpeg = btoa(String.fromCharCode(0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4, 5));
const png = btoa(
  String.fromCharCode(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0),
);

function setup(options: { context?: Context | null } = {}) {
  const posted: unknown[] = [];
  const fetcher: typeof fetch = (_input, init) => {
    posted.push(JSON.parse(String(init?.body)));
    return Promise.resolve(
      new Response(
        JSON.stringify({
          resourceType: "Bundle",
          type: "transaction-response",
          entry: [
            { response: { location: "Binary/b1/_history/1" } },
            { response: { location: "DocumentReference/d1/_history/1" } },
          ],
        }),
        { headers: { "content-type": "application/fhir+json" } },
      ),
    );
  };
  const handler = createAttachmentHandler({
    authenticate: (auth) => Promise.resolve(auth === "Bearer user"),
    writeContext: () =>
      Promise.resolve(options.context === undefined ? ctx : options.context),
    fetcher,
    baseUrl: "http://hapi/fhir",
    now: () => new Date("2026-11-14T12:00:00Z"),
  });
  return { handler, posted };
}
const request = (body: Record<string, unknown>, auth = "Bearer user") =>
  new Request("http://localhost/clinical-attachment", {
    method: "POST",
    headers: { authorization: auth, "content-type": "application/json" },
    body: JSON.stringify(body),
  });
const valid = {
  organizationId: ORG,
  hospitalizationId: EPISODE,
  clientEventId: NOTE,
  contentType: "image/jpeg",
  dataBase64: jpeg,
  takenAt: "2026-11-14T11:59:00Z",
};

Deno.test("stores the photo as Binary + DocumentReference linked to the note", async () => {
  const { handler, posted } = setup();
  const response = await handler(request(valid));
  assert(response.status === 201, `unexpected ${response.status}`);
  assert((await response.json()).id === "d1", "document id not returned");
  // deno-lint-ignore no-explicit-any
  const bundle = posted[0] as any;
  const document = bundle.entry[1].resource;
  assert(bundle.type === "transaction", "must be one atomic transaction");
  assert(bundle.entry[0].resource.resourceType === "Binary", "binary first");
  assert(document.subject.reference === "Patient/p1", "subject mismatch");
  assert(
    document.context.encounter[0].reference === "Encounter/e1",
    "encounter mismatch",
  );
  assert(
    document.context.related[0].identifier.value === NOTE,
    "note link missing",
  );
  assert(
    document.content[0].attachment.url === bundle.entry[0].fullUrl,
    "document must reference the binary",
  );
  assert(document.meta.tag[0].code === "HTEST", "synthetic tag missing");
});

Deno.test("authentication and write authorization fail before upstream", async () => {
  const anonymous = setup();
  assert(
    (await anonymous.handler(request(valid, "Bearer other"))).status === 401,
    "invalid token must be rejected",
  );
  const denied = setup({ context: null });
  assert(
    (await denied.handler(request(valid))).status === 404,
    "missing write context must be hidden",
  );
  assert(
    anonymous.posted.length === 0 && denied.posted.length === 0,
    "no upstream write expected",
  );
});

Deno.test("rejects mismatched signatures, unknown keys and future instants", async () => {
  const { handler, posted } = setup();
  const disguised = await handler(
    request({ ...valid, contentType: "image/png" }),
  );
  assert(disguised.status === 415, "JPEG declared as PNG must fail");
  const gif = await handler(request({ ...valid, contentType: "image/gif" }));
  assert(gif.status === 415, "unsupported type must fail");
  const extra = await handler(request({ ...valid, url: "http://evil" }));
  assert(extra.status === 400, "unknown keys must fail");
  const future = await handler(
    request({ ...valid, takenAt: "2026-11-15T12:00:00Z" }),
  );
  assert(future.status === 400, "future capture time must fail");
  const pngOk = await handler(
    request({ ...valid, contentType: "image/png", dataBase64: png }),
  );
  assert(pngOk.status === 201, "real PNG must be accepted");
  assert(posted.length === 1, "only the valid PNG reaches HAPI");
});

Deno.test("photo download is limited to the authorized encounter", async () => {
  const resources: Record<string, unknown> = {
    "DocumentReference/d1": {
      resourceType: "DocumentReference",
      id: "d1",
      subject: { reference: "Patient/p1" },
      category: [{ coding: [{ code: "clinical-photo" }] }],
      context: { encounter: [{ reference: "Encounter/e1" }] },
      content: [{ attachment: { url: "Binary/b1" } }],
    },
    "DocumentReference/d2": {
      resourceType: "DocumentReference",
      id: "d2",
      subject: { reference: "Patient/p2" },
      category: [{ coding: [{ code: "clinical-photo" }] }],
      context: { encounter: [{ reference: "Encounter/e1" }] },
      content: [{ attachment: { url: "Binary/b1" } }],
    },
    "Binary/b1": {
      resourceType: "Binary",
      id: "b1",
      contentType: "image/jpeg",
      data: jpeg,
    },
  };
  const fetcher: typeof fetch = (input) => {
    const key = new URL(String(input)).pathname.split("/fhir/")[1];
    return Promise.resolve(new Response(JSON.stringify(resources[key])));
  };
  const photo = await loadAttachment(ctx, "d1", fetcher, "http://hapi/fhir");
  assert(
    photo.contentType === "image/jpeg" && photo.dataBase64 === jpeg,
    "photo",
  );
  let rejected = false;
  try {
    await loadAttachment(ctx, "d2", fetcher, "http://hapi/fhir");
  } catch {
    rejected = true;
  }
  assert(rejected, "a photo of another patient must be rejected");
});
