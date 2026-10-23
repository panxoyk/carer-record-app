import type { Context } from "./handler.ts";

export type Purpose = "record" | "timeline";
export type Entry = {
  id: string;
  title: string;
  detail: string | null;
  date: string | null;
  isDateOnly: boolean;
  sourceKind: string;
};
export type TimelineItem = {
  id: string;
  occurredAt: string | null;
  precision: "date" | "instant" | null;
  resourceType: string;
  title: string;
  detail: string | null;
};
export type ClinicalRecord = {
  status: "complete" | "partial";
  truncated: boolean;
  freshness: { retrievedAt: string; sourceUpdatedAt: string | null };
  patient: {
    id: string;
    name: string;
    identifier: string | null;
    birthDate: string | null;
    gender: string | null;
  };
  hospitalization: {
    id: string;
    status: string;
    admittedAt: string;
    dischargedAt: string | null;
    unit: string | null;
    bed: string | null;
  };
  sections: { type: string; entries: Entry[] }[];
  timeline: TimelineItem[];
};

const TYPES = [
  "Condition",
  "Observation",
  "MedicationRequest",
  "Procedure",
  "DiagnosticReport",
  "AllergyIntolerance",
] as const;
const ID = /^[A-Za-z0-9.-]{1,64}$/;
const MAX_PAGES = 20,
  MAX_RESOURCES = 500,
  MAX_BYTES = 5_000_000,
  TIMEOUT_MS = 10_000;
// deno-lint-ignore no-explicit-any
type Resource = Record<string, any>;
type Fetcher = typeof fetch;
const ref = (value: unknown, type: string): string | null => {
  if (typeof value !== "string") return null;
  const m = new RegExp(`^${type}/([A-Za-z0-9.-]{1,64})$`).exec(value);
  return m?.[1] ?? null;
};
const codings = (cc: Resource): string[] =>
  (cc?.coding ?? []).map((x: Resource) => x.display || x.code).filter((
    x: unknown,
  ): x is string => typeof x === "string" && !!x.trim());
const codeText = (cc: Resource): string =>
  cc?.text?.trim() || codings(cc).join(" / ") || "Sin descripción";
function formatQuantity(q: Resource): string | null {
  if (!q || q.value == null) return null;
  return `${q.value}${q.unit ? ` ${q.unit}` : q.code ? ` ${q.code}` : ""}`;
}
function dateInfo(value: unknown): { value: string | null; dateOnly: boolean } {
  if (typeof value !== "string") return { value: null, dateOnly: false };
  const calendarIsValid = (date: string) => {
    const [y, m, d] = date.split("-").map(Number);
    if (y < 1 || m < 1 || m > 12) return false;
    if (d === undefined) return true;
    const leap = y % 4 === 0 && (y % 100 !== 0 || y % 400 === 0);
    const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    return d >= 1 && d <= days[m - 1];
  };
  if (/^\d{4}(?:-\d{2}(?:-\d{2})?)?$/.test(value)) {
    if (!calendarIsValid(value.length > 4 ? value.slice(0, 10) : value)) {
      throw new Error("invalid clinical date");
    }
    return { value, dateOnly: true };
  }
  const match =
    /^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?(Z|([+-])(\d{2}):(\d{2}))$/
      .exec(value);
  if (match) {
    const [
      ,
      date,
      hour,
      minute,
      second = "0",
      ,
      ,
      ,
      offsetHour = "0",
      offsetMinute = "0",
    ] = match;
    if (
      !calendarIsValid(date) || Number(hour) > 23 || Number(minute) > 59 ||
      Number(second) > 59 || Number(offsetHour) > 14 ||
      Number(offsetMinute) > 59 ||
      (Number(offsetHour) === 14 && Number(offsetMinute) !== 0) ||
      !Number.isFinite(Date.parse(value))
    ) throw new Error("invalid clinical date");
    return { value, dateOnly: false };
  }
  throw new Error("invalid clinical date");
}
function patientReference(r: Resource): string | null {
  return ref(r.subject?.reference ?? r.patient?.reference, "Patient");
}
function episodeReference(r: Resource): string | null {
  return ref(r.encounter?.reference, "Encounter");
}
function ensureResource(r: Resource, type: string, ctx: Context): void {
  if (
    !r || r.resourceType !== type || typeof r.id !== "string" || !ID.test(r.id)
  ) throw new Error("invalid FHIR resource");
  if (patientReference(r) !== ctx.patient_fhir_id) {
    throw new Error("foreign patient resource");
  }
  if (
    type !== "AllergyIntolerance" &&
    episodeReference(r) !== ctx.encounter_fhir_id
  ) throw new Error("foreign encounter resource");
}
function dateFor(r: Resource): string | null {
  const v = r.effectiveDateTime ?? r.effectiveDate ?? r.issued ??
    r.authoredOn ?? r.performedDateTime ?? r.performedPeriod?.start ??
    r.onsetDateTime ?? r.recordedDate ?? r.date;
  return dateInfo(v).value;
}
function detailFor(
  type: string,
  r: Resource,
  observations: Map<string, Resource>,
): string | null {
  const parts: string[] = [];
  if (type === "Observation") {
    if (r.valueQuantity) parts.push(formatQuantity(r.valueQuantity)!);
    else if (r.valueString != null) parts.push(String(r.valueString));
    else if (r.valueCodeableConcept) {
      parts.push(codeText(r.valueCodeableConcept));
    }
    for (const c of r.component ?? []) {
      const val = formatQuantity(c.valueQuantity) ?? c.valueString ??
        codeText(c.valueCodeableConcept);
      if (val) parts.push(`${codeText(c.code)}: ${val}`);
    }
    for (const range of r.referenceRange ?? []) {
      const low = formatQuantity(range.low), high = formatQuantity(range.high);
      parts.push(
        `Referencia: ${low ?? ""}${low && high ? "–" : ""}${high ?? ""}${
          range.text ? ` (${range.text})` : ""
        }`.trim(),
      );
    }
  } else if (type === "MedicationRequest") {
    const med = codeText(r.medicationCodeableConcept);
    const doses = (r.dosageInstruction ?? []).map((d: Resource) =>
      [
        d.text,
        d.route ? `vía ${codeText(d.route)}` : null,
        d.doseAndRate?.map((x: Resource) => formatQuantity(x.doseQuantity))
          .filter(Boolean).join(", "),
      ].filter(Boolean).join("; ")
    ).filter(Boolean);
    parts.push(
      `Prescripción: ${med}${doses.length ? ` — ${doses.join("; ")}` : ""}`,
    );
  } else if (type === "DiagnosticReport") {
    if (r.conclusion) parts.push(r.conclusion);
    for (const item of r.result ?? []) {
      const id = ref(item.reference, "Observation");
      if (!id) throw new Error("invalid DiagnosticReport result reference");
      const obs = observations.get(id);
      if (!obs) {
        throw new Error(
          "DiagnosticReport references an unauthorized observation",
        );
      }
      const d = detailFor("Observation", obs, observations);
      parts.push(`${codeText(obs.code)}${d ? `: ${d}` : ""}`);
    }
  } else if (type === "Condition") {
    parts.push(
      r.clinicalStatus?.coding?.map((c: Resource) => c.display || c.code)
        .filter(Boolean).join(" / ") || "",
    );
  } else if (type === "Procedure") parts.push(r.status || "");
  else if (type === "AllergyIntolerance") {
    parts.push(
      r.clinicalStatus?.coding?.map((c: Resource) => c.display || c.code)
        .filter(Boolean).join(" / ") || "",
    );
  }
  return parts.filter(Boolean).join(" · ") || null;
}
function sectionName(t: string): string {
  return ({
    Condition: "conditions",
    Observation: "observations",
    MedicationRequest: "medications",
    Procedure: "procedures",
    DiagnosticReport: "reports",
    AllergyIntolerance: "allergies",
  } as Record<string, string>)[t];
}
function titleFor(t: string, r: Resource): string {
  return codeText(
    t === "MedicationRequest"
      ? r.medicationCodeableConcept
      : t === "AllergyIntolerance"
      ? r.code
      : r.code ?? r.type,
  );
}
function entryId(t: string, id: string): string {
  return `demo-hapi/${t}/${id}`;
}

export async function loadClinicalRecord(
  ctx: Context,
  purpose: Purpose,
  fetcher: Fetcher,
  baseURL: string,
): Promise<ClinicalRecord> {
  if (!ID.test(ctx.patient_fhir_id) || !ID.test(ctx.encounter_fhir_id)) {
    throw new Error("invalid authorized context");
  }
  const base = new URL(baseURL);
  if (
    !["http:", "https:"].includes(base.protocol) || base.username ||
    base.password || base.search || base.hash
  ) throw new Error("invalid source base URL");
  const rootPath = base.pathname.replace(/\/$/, "");
  const root = new URL(`${rootPath}/`, base.origin);
  let bytes = 0, truncated = false;
  const fetchJson = async (url: URL): Promise<Resource> => {
    const relativePath = url.pathname.startsWith(rootPath + "/")
      ? url.pathname.slice(rootPath.length + 1)
      : "";
    if (
      url.origin !== base.origin ||
      (url.pathname !== rootPath &&
        !/^[A-Za-z]+(?:\/[A-Za-z0-9.-]{1,64})?$/.test(relativePath))
    ) throw new Error("upstream URL outside source");
    const response = await fetcher(url, {
      headers: { accept: "application/fhir+json" },
      redirect: "error",
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (!response.ok) throw new Error("FHIR upstream error");
    const declared = Number(response.headers.get("content-length") ?? 0);
    if (declared && bytes + declared > MAX_BYTES) {
      truncated = true;
      throw new Error("FHIR byte limit exceeded");
    }
    if (!response.body) throw new Error("FHIR response body missing");
    const reader = response.body.getReader();
    const decoder = new TextDecoder("utf-8", { fatal: true });
    let text = "";
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > MAX_BYTES) {
        await reader.cancel();
        truncated = true;
        throw new Error("FHIR byte limit exceeded");
      }
      text += decoder.decode(value, { stream: true });
    }
    try {
      return JSON.parse(text + decoder.decode()) as Resource;
    } catch {
      throw new Error("invalid FHIR JSON");
    }
  };
  const resource = async (type: string, id: string) => {
    const result = await fetchJson(
      new URL(`${type}/${encodeURIComponent(id)}`, root),
    );
    if (result.resourceType !== type || result.id !== id) {
      throw new Error("FHIR identity mismatch");
    }
    return result;
  };
  const search = async (
    type: typeof TYPES[number],
    patientOnly = false,
  ): Promise<Resource[]> => {
    const params = new URLSearchParams({
      patient: `Patient/${ctx.patient_fhir_id}`,
      _count: "100",
    });
    if (!patientOnly) {
      params.set("encounter", `Encounter/${ctx.encounter_fhir_id}`);
    }
    let next: URL | null = new URL(`${type}?${params}`, root), pages = 0;
    const seen = new Set<string>(), found = new Map<string, Resource>();
    while (next) {
      if (++pages > MAX_PAGES) {
        truncated = true;
        break;
      }
      if (seen.has(next.href)) throw new Error("FHIR pagination cycle");
      seen.add(next.href);
      const bundle = await fetchJson(next);
      if (
        bundle.resourceType !== "Bundle" || bundle.type !== "searchset" ||
        !Array.isArray(bundle.entry ?? [])
      ) throw new Error("invalid FHIR search bundle");
      let limitReached = false;
      for (const e of bundle.entry ?? []) {
        if (!e.resource) continue;
        ensureResource(e.resource, type, ctx);
        const previous = found.get(e.resource.id);
        if (previous) {
          const canonical = (v: unknown): string =>
            Array.isArray(v)
              ? `[${v.map(canonical).join(",")}]`
              : v && typeof v === "object"
              ? `{${
                Object.keys(v).sort().map((k) =>
                  `${JSON.stringify(k)}:${canonical((v as Resource)[k])}`
                ).join(",")
              }}`
              : JSON.stringify(v);
          if (
            previous.meta?.versionId !== e.resource.meta?.versionId ||
            canonical(previous) !== canonical(e.resource)
          ) throw new Error("conflicting duplicate FHIR resource");
          continue;
        }
        if (found.size >= MAX_RESOURCES) {
          truncated = true;
          limitReached = true;
          break;
        }
        found.set(e.resource.id, e.resource);
      }
      const link = bundle.link?.find((x: Resource) => x.relation === "next")
        ?.url;
      if (limitReached || found.size >= MAX_RESOURCES && link != null) {
        if (link != null) truncated = true;
        break;
      }
      if (link == null) next = null;
      else {
        if (typeof link !== "string") throw new Error("invalid next link");
        const candidate: URL = new URL(link, next.href);
        if (
          candidate.origin !== base.origin || candidate.username ||
          candidate.password || candidate.hash ||
          candidate.pathname !== rootPath
        ) throw new Error("untrusted FHIR next link");
        const qs = candidate.searchParams;
        const allowed = new Set([
          "_getpages",
          "_getpagesoffset",
          "_count",
          "_pretty",
          "_bundletype",
          "_format",
        ]);
        if (
          [...qs.keys()].some((key) => !allowed.has(key)) ||
          [...qs.keys()].some((key) => qs.getAll(key).length !== 1) ||
          qs.getAll("_getpages").length !== 1 ||
          !/^[A-Za-z0-9._-]{1,128}$/.test(qs.get("_getpages") ?? "")
        ) throw new Error("untrusted FHIR cursor");
        if (
          qs.has("_getpagesoffset") &&
          !/^(0|[1-9]\d{0,5})$/.test(qs.get("_getpagesoffset")!)
        ) throw new Error("untrusted FHIR cursor offset");
        if (
          qs.has("_count") && !/^(?:[1-9]\d{0,2}|1000)$/.test(qs.get("_count")!)
        ) throw new Error("untrusted FHIR cursor count");
        if (
          qs.has("_pretty") && !["true", "false"].includes(qs.get("_pretty")!)
        ) throw new Error("untrusted FHIR cursor option");
        if (qs.has("_bundletype") && qs.get("_bundletype") !== "searchset") {
          throw new Error("untrusted FHIR cursor type");
        }
        if (
          qs.has("_format") &&
          !["application/fhir+json", "json"].includes(qs.get("_format")!)
        ) throw new Error("untrusted FHIR cursor format");
        next = candidate;
      }
    }
    return [...found.values()];
  };
  const retrievedAt = new Date().toISOString();
  const [patient, encounter] = await Promise.all([
    resource("Patient", ctx.patient_fhir_id),
    resource("Encounter", ctx.encounter_fhir_id),
  ]);
  const subject = ref(encounter.subject?.reference, "Patient");
  if (
    subject !== ctx.patient_fhir_id || encounter.class?.code !== "IMP" ||
    !["in-progress", "finished"].includes(encounter.status)
  ) throw new Error("authorized Encounter invalid");
  const start = dateInfo(encounter.period?.start);
  if (!start.value || start.dateOnly) {
    throw new Error("Encounter start instant required");
  }
  const end = dateInfo(encounter.period?.end);
  if (
    encounter.status === "in-progress" && end.value ||
    encounter.status === "finished" && (!end.value || end.dateOnly)
  ) throw new Error("Encounter period/status mismatch");
  if (end.value && Date.parse(end.value) < Date.parse(start.value)) {
    throw new Error("invalid Encounter period");
  }
  const [
    conditions,
    observations,
    medications,
    procedures,
    reports,
    allergies,
  ] = await Promise.all(
    TYPES.map((t) => search(t, t === "AllergyIntolerance")),
  );
  const byType = new Map<string, Resource[]>(
    TYPES.map((
      t,
      i,
    ) => [
      t,
      [
        conditions,
        observations,
        medications,
        procedures,
        reports,
        allergies,
      ][i],
    ]),
  );
  let remaining = MAX_RESOURCES;
  for (const type of TYPES) {
    const rows = byType.get(type) ?? [];
    if (rows.length > remaining) {
      byType.set(type, rows.slice(0, remaining));
      truncated = true;
    } else remaining -= rows.length;
  }
  const observationMap = new Map(observations.map((o) => [o.id, o]));
  const locRefs: string[] = [];
  for (const l of encounter.location ?? []) {
    const id = ref(l.location?.reference, "Location");
    if (!id) throw new Error("invalid Encounter Location reference");
    if (!locRefs.includes(id)) locRefs.push(id);
  }
  const locations = await Promise.all(
    locRefs.map((id) => resource("Location", id)),
  );
  const locById = new Map(locations.map((l) => [l.id, l]));
  let unit: string | null = null, bed: string | null = null;
  for (const l of locations) {
    const parentId = l.partOf ? ref(l.partOf.reference, "Location") : null;
    if (l.partOf && !parentId) {
      throw new Error("invalid Location parent reference");
    }
    const parent = parentId
      ? locById.get(parentId) ?? await resource("Location", parentId)
      : null;
    if (parentId && parent?.resourceType !== "Location") {
      throw new Error("invalid Location parent");
    }
    if (l.physicalType?.coding?.some((c: Resource) => c.code === "wa")) {
      unit = l.name ?? unit;
    } else {
      bed = l.name ?? bed;
      if (
        parent?.physicalType?.coding?.some((c: Resource) => c.code === "wa")
      ) unit = parent.name ?? unit;
    }
  }
  const sections = TYPES.map((type) => ({
    type: sectionName(type),
    entries: (byType.get(type) ?? []).map((r) => {
      const d = dateInfo(dateFor(r));
      return {
        id: entryId(type, r.id),
        title: titleFor(type, r),
        detail: detailFor(type, r, observationMap),
        date: d.value,
        isDateOnly: d.dateOnly,
        sourceKind: type,
      };
    }).sort((a, b) => (b.date ?? "").localeCompare(a.date ?? "")),
  }));
  const timeline: TimelineItem[] = [];
  if (purpose === "timeline") {
    for (const type of TYPES.filter((t) => t !== "AllergyIntolerance")) {
      for (const r of byType.get(type) ?? []) {
        const d = dateInfo(dateFor(r));
        timeline.push({
          id: entryId(type, r.id),
          occurredAt: d.value,
          precision: d.value ? d.dateOnly ? "date" : "instant" : null,
          resourceType: type,
          title: titleFor(type, r),
          detail: detailFor(type, r, observationMap),
        });
      }
    }
  }
  timeline.sort((a, b) =>
    (b.occurredAt ?? "").localeCompare(a.occurredAt ?? "")
  );
  const official = patient.name?.find((n: Resource) => n.use === "official") ??
    patient.name?.[0] ?? {};
  const name = [
    ...(official.given ?? []),
    ...(official.family ? [official.family] : []),
  ].join(" ").trim();
  const sourceTimes = [
    patient,
    encounter,
    ...TYPES.flatMap((t) => byType.get(t) ?? []),
    ...locations,
  ].map((r) => r.meta?.lastUpdated).filter((v): v is string =>
    typeof v === "string"
  );
  for (const value of sourceTimes) {
    const timestamp = dateInfo(value);
    if (timestamp.dateOnly) {
      throw new Error("FHIR meta.lastUpdated must be an instant");
    }
  }
  const sourceUpdatedAt =
    sourceTimes.sort((a, b) => Date.parse(a) - Date.parse(b)).at(-1) ?? null;
  return {
    status: truncated ? "partial" : "complete",
    truncated,
    freshness: {
      retrievedAt,
      sourceUpdatedAt,
    },
    patient: {
      id: ctx.patient_id,
      name,
      identifier: patient.identifier?.[0]?.value ?? null,
      birthDate: patient.birthDate ?? null,
      gender: patient.gender ?? null,
    },
    hospitalization: {
      id: ctx.hospitalization_id,
      status: encounter.status === "in-progress" ? "admitted" : "discharged",
      admittedAt: start.value,
      dischargedAt: end.value,
      unit,
      bed,
    },
    sections,
    timeline,
  };
}
