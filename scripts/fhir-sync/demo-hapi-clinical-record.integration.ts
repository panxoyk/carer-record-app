import { loadClinicalRecord } from "../../supabase/functions/clinical-record/fhir.ts";

if (Deno.env.get("FHIR_DEMO_HAPI_INTEGRATION") !== "1") {
  throw new Error("Set FHIR_DEMO_HAPI_INTEGRATION=1 to run against the disposable HAPI only");
}

const [baseUrl, today, previousDay] = Deno.args;
if (!baseUrl || !/^\d{4}-\d{2}-\d{2}$/.test(today ?? "") || !/^\d{4}-\d{2}-\d{2}$/.test(previousDay ?? "")) {
  throw new Error("Usage: deno run ... demo-hapi-clinical-record.integration.ts BASE_URL TODAY PREVIOUS_DAY");
}

const ctx = {
  source_id: "685e5726-68ba-54c9-a528-bc7b7f6c20f8",
  patient_fhir_id: "a1000000-0000-4000-8000-000000000001",
  encounter_fhir_id: "enc-med-ana",
  organization_id: "11111111-1111-4111-8111-111111111111",
  hospitalization_id: "22222222-2222-4222-8222-222222222222",
  patient_id: "33333333-3333-4333-8333-333333333333",
};

function range(day: string) {
  const start = new Date(`${day}T00:00:00.000Z`);
  const end = new Date(start.getTime() + 86_400_000);
  return { fromUtc: start.toISOString(), toUtc: end.toISOString() };
}

const [current, old] = await Promise.all([
  loadClinicalRecord(ctx, "timeline", fetch, baseUrl, range(today), "America/Santiago"),
  loadClinicalRecord(ctx, "timeline", fetch, baseUrl, range(previousDay), "America/Santiago"),
]);
const count = (record: typeof current) =>
  record.sections.find((section) => section.type === "observations")?.entries.length ?? 0;
console.log(JSON.stringify({ todayObservations: count(current), previousDayObservations: count(old) }));
