import { type Context, createHandler } from "./handler.ts";
function assertEquals(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Assertion failed: ${JSON.stringify(actual)} !== ${
        JSON.stringify(expected)
      }`,
    );
  }
}
const ctx: Context = {
  source_id: "685e5726-68ba-54c9-a528-bc7b7f6c20f8",
  patient_fhir_id: "p1",
  encounter_fhir_id: "e1",
  organization_id: "11111111-1111-4111-8111-111111111111",
  hospitalization_id: "22222222-2222-4222-8222-222222222222",
  patient_id: "33333333-3333-4333-8333-333333333333",
};
const body = (purpose?: unknown) =>
  JSON.stringify({
    organizationId: ctx.organization_id,
    hospitalizationId: ctx.hospitalization_id,
    ...(purpose === undefined ? {} : { purpose }),
  });
const rangedBody = (range: unknown) =>
  JSON.stringify({
    organizationId: ctx.organization_id,
    hospitalizationId: ctx.hospitalization_id,
    purpose: "timeline",
    range,
  });
const request = (value: BodyInit, extra: Record<string, string> = {}) =>
  new Request("http://local/clinical-record", {
    method: "POST",
    headers: {
      authorization: "Bearer valid",
      "content-type": "application/json",
      ...extra,
    },
    body: value,
  });
const upstream = (
  encounter = {
    resourceType: "Encounter",
    id: "e1",
    status: "in-progress",
    class: { code: "IMP" },
    subject: { reference: "Patient/p1" },
    period: { start: "2026-01-02T09:30:00Z" },
  },
): typeof fetch =>
(input) => {
  const path = new URL(String(input)).pathname.split("/fhir/")[1]?.split(
    "?",
  )[0];
  const data: Record<string, unknown> = {
    "Patient/p1": {
      resourceType: "Patient",
      id: "p1",
      name: [{ given: ["A"], family: "Patient" }],
    },
    "Encounter/e1": encounter,
  };
  const payload = data[path ?? ""] ??
    { resourceType: "Bundle", type: "searchset", entry: [] };
  return Promise.resolve(
    new Response(JSON.stringify(payload), {
      headers: { "content-type": "application/fhir+json" },
    }),
  );
};
const handler = (
  context: (
    call: number,
    purpose: string,
  ) => Context | null | Promise<Context | null>,
  fetcher = upstream(),
  authenticate = (_auth: string) => Promise.resolve(true),
  baseUrl: string | undefined = "http://hapi/fhir",
  now?: () => Date,
) => {
  let calls = 0;
  return {
    run: createHandler({
      authenticate,
      baseUrl,
      now,
      fetcher,
      context: async (_o, _h, p) => await context(++calls, p),
    }),
    calls: () => calls,
  };
};
Deno.test("auth denial and Service Role bearer fail before upstream", async () => {
  let fetched = false;
  const h = handler(() => ctx, () => {
    fetched = true;
    return Promise.resolve(new Response());
  }, () => Promise.resolve(false));
  assertEquals((await h.run(request(body()))).status, 401);
  assertEquals(
    (await h.run(request(body(), { authorization: "Bearer service-role" })))
      .status,
    401,
  );
  assertEquals(fetched, false);
});
Deno.test("authorization is checked before any FHIR request", async () => {
  let fetched = false;
  const h = handler(() => null, () => {
    fetched = true;
    return Promise.resolve(new Response());
  });
  assertEquals((await h.run(request(body()))).status, 404);
  assertEquals(fetched, false);
});
Deno.test("revocation on post-load recheck denies the fetched response", async () => {
  let fetched = false;
  const h = handler((n) => n === 1 ? ctx : null, (input) => {
    fetched = true;
    return upstream()(input);
  });
  assertEquals((await h.run(request(body()))).status, 404);
  assertEquals(fetched, true);
  assertEquals(h.calls(), 2);
});
Deno.test("record returns empty timeline, and timeline denial happens before fetch", async () => {
  let fetched = false;
  const h = handler((_n, p) => p === "record" ? ctx : null, (input) => {
    fetched = true;
    return upstream()(input);
  });
  const record = await h.run(request(body("record")));
  assertEquals(record.status, 200);
  const dto = await record.json();
  assertEquals(dto.timeline, []);
  fetched = false;
  assertEquals((await h.run(request(body("timeline")))).status, 404);
  assertEquals(fetched, false);
});
Deno.test("Encounter subject mismatch fails closed", async () => {
  const h = handler(
    () => ctx,
    upstream({
      resourceType: "Encounter",
      id: "e1",
      status: "in-progress",
      class: { code: "IMP" },
      subject: { reference: "Patient/other" },
      period: { start: "2026-01-02T09:30:00Z" },
    }),
  );
  assertEquals((await h.run(request(body()))).status, 502);
});
Deno.test("missing and invalid server URL return sanitized 503", async () => {
  const missing = handler(
    () => ctx,
    upstream(),
    () => Promise.resolve(true),
    "",
  );
  const invalid = handler(
    () => ctx,
    upstream(),
    () => Promise.resolve(true),
    "file:///etc/passwd",
  );
  assertEquals((await missing.run(request(body()))).status, 503);
  assertEquals((await invalid.run(request(body()))).status, 503);
});
Deno.test("unknown and malformed inputs rejected; body cap streams", async () => {
  const h = handler(() => ctx);
  assertEquals(
    (await h.run(
      request(JSON.stringify({ ...JSON.parse(body()), sourceId: "arbitrary" })),
    )).status,
    400,
  );
  assertEquals(
    (await h.run(
      request(JSON.stringify({ ...JSON.parse(body()), timezone: "UTC" })),
    )).status,
    400,
  );
  assertEquals((await h.run(request("{"))).status, 400);
  const tooLarge = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(new Uint8Array(4097));
    },
  });
  assertEquals((await h.run(request(tooLarge))).status, 413);
  assertEquals((await h.run(request(body(12)))).status, 400);
});
Deno.test("range requires strict valid UTC instants and uses fixed demo timezone", async () => {
  const now = new Date().toISOString();
  const from = new Date(Date.parse(now) - 60_000).toISOString();
  const invalid = [
    { fromUtc: from, toUtc: now, extra: true },
    { fromUtc: "2026-02-30T00:00:00Z", toUtc: now },
    { fromUtc: now, toUtc: from },
    { fromUtc: from, toUtc: new Date(Date.now() + 60_000).toISOString() },
    { fromUtc: "2026-01-01T00:00:00", toUtc: now },
  ];
  for (const range of invalid) {
    assertEquals(
      (await handler(() => ctx).run(request(rangedBody(range)))).status,
      400,
    );
  }
  const h = handler(() => ctx);
  assertEquals(
    (await h.run(request(rangedBody({ fromUtc: from, toUtc: now })))).status,
    200,
  );
});
Deno.test("range future validation uses the injected handler clock", async () => {
  const fixedNow = new Date("2026-01-03T00:00:00Z");
  const h = handler(
    () => ctx,
    upstream(),
    undefined,
    undefined,
    () => fixedNow,
  );
  assertEquals(
    (await h.run(request(rangedBody({
      fromUtc: "2026-01-02T00:00:00Z",
      toUtc: "2026-01-03T00:00:00Z",
    })))).status,
    200,
  );
  assertEquals(
    (await h.run(request(rangedBody({
      fromUtc: "2026-01-02T00:00:00Z",
      toUtc: "2026-01-03T00:00:00.001Z",
    })))).status,
    400,
  );
});
