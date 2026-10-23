import { loadClinicalRecord } from "./fhir.ts";
import type { Context } from "./handler.ts";
const assert = (ok: unknown, message: string) => {
  if (!ok) throw new Error(message);
};
const ctx: Context = {
  source_id: "685e5726-68ba-54c9-a528-bc7b7f6c20f8",
  patient_fhir_id: "p1",
  encounter_fhir_id: "e1",
  organization_id: "11111111-1111-4111-8111-111111111111",
  hospitalization_id: "22222222-2222-4222-8222-222222222222",
  patient_id: "33333333-3333-4333-8333-333333333333",
};
const fixtures: Record<string, unknown> = {
  "Patient/p1": {
    resourceType: "Patient",
    id: "p1",
    name: [{ given: ["Test"], family: "Person" }],
    birthDate: "1980-04-03",
  },
  "Encounter/e1": {
    resourceType: "Encounter",
    id: "e1",
    status: "in-progress",
    class: { code: "IMP" },
    subject: { reference: "Patient/p1" },
    period: { start: "2026-01-02T09:30:00Z" },
  },
  "Condition": {
    resourceType: "Bundle",
    type: "searchset",
    entry: [{
      resource: {
        resourceType: "Condition",
        id: "c1",
        subject: { reference: "Patient/p1" },
        encounter: { reference: "Encounter/e1" },
        code: { text: "Test diagnosis" },
        onsetDateTime: "2026-01-02",
      },
    }],
  },
  "Observation": {
    resourceType: "Bundle",
    type: "searchset",
    entry: [{
      resource: {
        resourceType: "Observation",
        id: "o1",
        subject: { reference: "Patient/p1" },
        encounter: { reference: "Encounter/e1" },
        code: { text: "Blood pressure" },
        effectiveDate: "2026-01-02",
        component: [{
          code: { text: "Systolic" },
          valueQuantity: { value: 120, unit: "mmHg" },
        }, {
          code: { text: "Diastolic" },
          valueQuantity: { value: 80, unit: "mmHg" },
        }],
      },
    }],
  },
};
function client(overrides: Record<string, unknown> = {}) {
  const calls: string[] = [];
  const fetcher: typeof fetch = (input) => {
    const u = new URL(String(input));
    calls.push(u.href);
    const key = u.pathname.split("/fhir/")[1]?.split("?")[0] ?? "";
    const payload = overrides[key] ?? fixtures[key] ??
      { resourceType: "Bundle", type: "searchset", entry: [] };
    return Promise.resolve(
      new Response(JSON.stringify(payload), {
        headers: { "content-type": "application/fhir+json" },
      }),
    );
  };
  return { fetcher, calls };
}
Deno.test("preserves date precision, renders components, and omits timeline for record", async () => {
  const { fetcher } = client();
  const result = await loadClinicalRecord(
    ctx,
    "record",
    fetcher,
    "http://hapi/fhir",
  );
  assert(result.patient.id === ctx.patient_id, "patient ID must be internal");
  assert(
    result.sections.find((s) => s.type === "observations")?.entries[0].detail
      ?.includes("Systolic: 120 mmHg"),
    "component details missing",
  );
  const condition =
    result.sections.find((s) => s.type === "conditions")!.entries[0];
  assert(
    condition.date === "2026-01-02" && condition.isDateOnly,
    "date-only precision was changed",
  );
  assert(
    result.timeline.length === 0,
    "record purpose must not expose timeline",
  );
});
Deno.test("rejects a foreign patient resource even when search filters are ignored", async () => {
  const { fetcher } = client({
    Observation: {
      resourceType: "Bundle",
      type: "searchset",
      entry: [{
        resource: {
          resourceType: "Observation",
          id: "o2",
          subject: { reference: "Patient/other" },
          encounter: { reference: "Encounter/e1" },
        },
      }],
    },
  });
  let failed = false;
  try {
    await loadClinicalRecord(ctx, "timeline", fetcher, "http://hapi/fhir");
  } catch {
    failed = true;
  }
  assert(failed, "foreign patient must fail closed");
});
Deno.test("rejects pagination links to another host", async () => {
  const { fetcher } = client({
    Condition: {
      resourceType: "Bundle",
      type: "searchset",
      entry: [],
      link: [{
        relation: "next",
        url:
          "http://evil/fhir/Condition?patient=Patient/p1&encounter=Encounter/e1",
      }],
    },
  });
  let failed = false;
  try {
    await loadClinicalRecord(ctx, "timeline", fetcher, "http://hapi/fhir");
  } catch {
    failed = true;
  }
  assert(failed, "foreign next URL must fail closed");
});
Deno.test("accepts an HAPI opaque paging token only at the configured base path", async () => {
  const { fetcher, calls } = client({
    Condition: {
      resourceType: "Bundle",
      type: "searchset",
      entry: [],
      link: [{
        relation: "next",
        url:
          "http://hapi/fhir?_getpages=abc-123&_getpagesoffset=100&_count=100&_pretty=true&_bundletype=searchset",
      }],
    },
    "": { resourceType: "Bundle", type: "searchset", entry: [] },
  });
  const result = await loadClinicalRecord(
    ctx,
    "record",
    fetcher,
    "http://hapi/fhir",
  );
  assert(result.status === "complete", "valid HAPI cursor should be accepted");
  assert(
    calls.some((url) => url.includes("_getpages=abc-123")),
    "opaque cursor was not followed",
  );
});
Deno.test("rejects arbitrary or path-escaping cursor links", async () => {
  for (
    const url of [
      "http://hapi/fhir/Condition?_getpages=abc",
      "http://hapi/fhir?_getpages=..%2Fadmin",
      "http://hapi/fhir?_getpages=abc&next=http%3A%2F%2Fevil",
    ]
  ) {
    const { fetcher } = client({
      Condition: {
        resourceType: "Bundle",
        type: "searchset",
        entry: [],
        link: [{ relation: "next", url }],
      },
    });
    let failed = false;
    try {
      await loadClinicalRecord(ctx, "record", fetcher, "http://hapi/fhir");
    } catch {
      failed = true;
    }
    assert(failed, `untrusted cursor accepted: ${url}`);
  }
});
Deno.test("rejects invalid calendar dates and preserves year/month precision", async () => {
  for (
    const date of [
      "2026-99",
      "2026-02-30",
      "2026-02-29",
      "2026-01-01T25:00:00Z",
    ]
  ) {
    const { fetcher } = client({
      Condition: {
        resourceType: "Bundle",
        type: "searchset",
        entry: [{
          resource: {
            resourceType: "Condition",
            id: "c1",
            subject: { reference: "Patient/p1" },
            encounter: { reference: "Encounter/e1" },
            code: { text: "Condition" },
            onsetDateTime: date,
          },
        }],
      },
    });
    let failed = false;
    try {
      await loadClinicalRecord(ctx, "record", fetcher, "http://hapi/fhir");
    } catch {
      failed = true;
    }
    assert(failed, `invalid date accepted: ${date}`);
  }
  const { fetcher } = client({
    Condition: {
      resourceType: "Bundle",
      type: "searchset",
      entry: [{
        resource: {
          resourceType: "Condition",
          id: "c1",
          subject: { reference: "Patient/p1" },
          encounter: { reference: "Encounter/e1" },
          code: { text: "Condition" },
          onsetDateTime: "2026-02",
        },
      }],
    },
  });
  const result = await loadClinicalRecord(
    ctx,
    "record",
    fetcher,
    "http://hapi/fhir",
  );
  const entry =
    result.sections.find((s) => s.type === "conditions")!.entries[0];
  assert(
    entry.date === "2026-02" && entry.isDateOnly,
    "partial FHIR date precision changed",
  );
});
Deno.test("decodes multibyte UTF-8 split at arbitrary response chunk boundaries", async () => {
  const base = client({
    "Patient/p1": {
      resourceType: "Patient",
      id: "p1",
      name: [{ given: ["José"], family: "Peña" }],
    },
  });
  const fetcher: typeof fetch = async (input, init) => {
    const response = await base.fetcher(input, init);
    const bytes = new Uint8Array(await response.arrayBuffer());
    let offset = 0;
    const stream = new ReadableStream<Uint8Array>({
      pull(controller) {
        if (offset >= bytes.length) return controller.close();
        controller.enqueue(bytes.slice(offset, ++offset));
      },
    });
    return new Response(stream, {
      status: response.status,
      headers: response.headers,
    });
  };
  const response = await loadClinicalRecord(
    ctx,
    "record",
    fetcher,
    "http://hapi/fhir",
  );
  assert(response.patient.name === "José Peña", "split UTF-8 decode failed");
});
Deno.test("fails closed when duplicate resource id changes version or content", async () => {
  const { fetcher } = client({
    Condition: {
      resourceType: "Bundle",
      type: "searchset",
      entry: [
        {
          resource: {
            resourceType: "Condition",
            id: "c1",
            meta: { versionId: "1" },
            subject: { reference: "Patient/p1" },
            encounter: { reference: "Encounter/e1" },
            code: { text: "First" },
          },
        },
        {
          resource: {
            resourceType: "Condition",
            id: "c1",
            meta: { versionId: "2" },
            subject: { reference: "Patient/p1" },
            encounter: { reference: "Encounter/e1" },
            code: { text: "Second" },
          },
        },
      ],
    },
  });
  let failed = false;
  try {
    await loadClinicalRecord(ctx, "record", fetcher, "http://hapi/fhir");
  } catch {
    failed = true;
  }
  assert(failed, "conflicting duplicate resource accepted");
});
Deno.test("closed inpatient Encounter maps to discharged and date-only patient birth stays date-only", async () => {
  const { fetcher } = client({
    "Encounter/e1": {
      resourceType: "Encounter",
      id: "e1",
      status: "finished",
      class: { code: "IMP" },
      subject: { reference: "Patient/p1" },
      period: { start: "2026-01-02T09:30:00Z", end: "2026-01-03T10:00:00Z" },
    },
  });
  const result = await loadClinicalRecord(
    ctx,
    "record",
    fetcher,
    "http://hapi/fhir",
  );
  assert(
    result.hospitalization.status === "discharged" &&
      result.patient.birthDate === "1980-04-03",
    "closed/date mapping incorrect",
  );
});
